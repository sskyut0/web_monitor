#!/usr/bin/env ruby
# frozen_string_literal: true

require 'net/http'
require 'json'
require 'digest'
require 'time'
require 'nokogiri'
require 'uri'
require 'openssl'
require 'base64'

class WebMonitor
  def initialize
    @data_dir = File.join(__dir__, '..', 'docs', 'data')
    @sites_file = File.join(@data_dir, 'sites.json')
    @status_file = File.join(@data_dir, 'status.json')
    @history_file = File.join(@data_dir, 'history.json')
    @encryption_key = ENV['MONITOR_ENCRYPTION_KEY'] || 'default-key-change-in-production'
  end

  def run
    puts "Starting web monitoring at #{Time.now}"

    sites = load_sites
    current_status = load_status
    history = load_history

    updated_sites = []

    sites['sites'].each do |site|
      # Decrypt URL if encrypted
      actual_url = site['encrypted'] ? decrypt_url(site['url']) : site['url']
      puts "Checking site: #{site['name']}"

      begin
        site_status = check_site(site.merge('url' => actual_url), current_status, history, site)
        updated_sites << site_status

        puts "  Status: #{site_status['status']}"
        puts "  Hash: #{site_status['hash'][0..8]}..."
      rescue StandardError => e
        puts "  Error: #{e.message}"
        error_status = create_error_status(site, e.message)
        # Add encrypted flag to error status if original site was encrypted
        error_status['encrypted'] = true if site['encrypted']
        updated_sites << error_status
      end
    end

    # Find the most recent content change among all sites
    most_recent_change = updated_sites
                         .map { |site| site['last_change'] }
                         .compact
                         .max

    # Update status file
    new_status = {
      'last_updated' => most_recent_change,
      'sites' => updated_sites
    }

    save_status(new_status)
    save_history(history)

    puts "Monitoring completed at #{Time.now}"
  end

  private

  def load_sites
    JSON.parse(File.read(@sites_file))
  end

  def load_status
    return { 'sites' => [] } unless File.exist?(@status_file)

    JSON.parse(File.read(@status_file))
  end

  def load_history
    return {} unless File.exist?(@history_file)

    JSON.parse(File.read(@history_file))
  end

  def save_status(status)
    File.write(@status_file, JSON.pretty_generate(status))
  end

  def save_history(history)
    File.write(@history_file, JSON.pretty_generate(history))
  end

  def check_site(site, current_status, history, original_site = nil)
    # Fetch web content
    html_content = fetch_web_content(site['url'])

    # Extract and clean content
    cleaned_content = extract_content(
      html_content,
      site['selector'],
      site['exclude_selectors'] || []
    )

    # Calculate hash
    new_hash = get_content_hash(cleaned_content)

    # Find previous status
    previous_site = current_status['sites'].find { |s| s['id'] == site['id'] }
    previous_hash = previous_site ? previous_site['hash'] : nil

    # Determine if content changed
    change_detected = previous_hash && detect_change(previous_hash, new_hash)
    status = change_detected ? 'updated' : 'unchanged'

    # Update history
    history[site['id']] ||= []
    history[site['id']] << {
      'timestamp' => Time.now.utc.iso8601,
      'status' => status,
      'hash' => new_hash,
      'change_detected' => change_detected || false
    }

    # Keep only last 100 history entries per site
    history[site['id']] = history[site['id']].last(100)

    # Return updated site status (use original encrypted URL if available)
    display_url = original_site ? original_site['url'] : site['url']
    encrypted_flag = original_site ? original_site['encrypted'] : false
    
    status_data = {
      'id' => site['id'],
      'name' => site['name'],
      'url' => display_url,
      'status' => status,
      'last_check' => Time.now.utc.iso8601,
      'last_change' => change_detected ? Time.now.utc.iso8601 : previous_site&.dig('last_change'),
      'hash' => new_hash,
      'error' => nil
    }
    
    status_data['encrypted'] = true if encrypted_flag
    status_data
  end

  def fetch_web_content(url)
    uri = URI(url)

    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
      http.open_timeout = 10
      http.read_timeout = 30

      request = Net::HTTP::Get.new(uri)
      request['User-Agent'] = 'WebMonitor/1.0'

      response = http.request(request)

      raise "HTTP #{response.code}: #{response.message}" unless response.code.to_i.between?(200, 299)

      response.body
    end
  end

  def extract_content(html, _selector, _exclude_selectors = [])
    doc = Nokogiri::HTML(html)

    # Extract target content
    # target = doc.css(selector)
    # return '' if target.empty?

    # Remove excluded elements
    # exclude_selectors.each do |exclude_sel|
    #   target.css(exclude_sel).remove
    # end

    # Get text content and normalize
    content = doc.text.strip

    # Normalize whitespace and remove dynamic content
    content.gsub(/\s+/, ' ') # Multiple spaces to single space
           .gsub(/\d{4}-\d{2}-\d{2}/, '') # Remove dates
           .gsub(/\d{1,2}:\d{2}(:\d{2})?/, '') # Remove times
           .gsub(/\b\d+\s*(views?|comments?|likes?)\b/i, '') # Remove counters
           .gsub(/\s+/, ' ') # Clean up spaces again
           .strip
  end

  def get_content_hash(content)
    Digest::MD5.hexdigest(content)
  end

  def detect_change(old_hash, new_hash)
    old_hash != new_hash
  end

  def create_error_status(site, error_message)
    {
      'id' => site['id'],
      'name' => site['name'],
      'url' => site['url'],
      'status' => 'error',
      'last_check' => Time.now.utc.iso8601,
      'last_change' => nil,
      'hash' => nil,
      'error' => error_message
    }
  end

  def encrypt_url(url)
    cipher = OpenSSL::Cipher.new('aes-256-cbc')
    cipher.encrypt
    key = Digest::SHA256.digest(@encryption_key)
    cipher.key = key
    iv = cipher.random_iv

    encrypted = cipher.update(url) + cipher.final
    Base64.encode64(iv + encrypted).strip
  end

  def decrypt_url(encrypted_data)
    data = Base64.decode64(encrypted_data)
    cipher = OpenSSL::Cipher.new('aes-256-cbc')
    cipher.decrypt
    key = Digest::SHA256.digest(@encryption_key)
    cipher.key = key

    iv = data[0..15]
    encrypted = data[16..]
    cipher.iv = iv

    cipher.update(encrypted) + cipher.final
  end
end

# Run the monitor if called directly
if __FILE__ == $PROGRAM_NAME
  monitor = WebMonitor.new
  monitor.run
end
