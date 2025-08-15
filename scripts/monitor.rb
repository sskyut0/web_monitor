#!/usr/bin/env ruby

require 'net/http'
require 'json'
require 'digest'
require 'time'
require 'nokogiri'
require 'uri'

class WebMonitor
  def initialize
    @data_dir = File.join(__dir__, '..', 'data')
    @sites_file = File.join(@data_dir, 'sites.json')
    @status_file = File.join(@data_dir, 'status.json')
    @history_file = File.join(@data_dir, 'history.json')
  end

  def run
    puts "Starting web monitoring at #{Time.now}"
    
    sites = load_sites
    current_status = load_status
    history = load_history
    
    updated_sites = []
    
    sites['sites'].each do |site|
      puts "Checking site: #{site['name']} (#{site['url']})"
      
      begin
        site_status = check_site(site, current_status, history)
        updated_sites << site_status
        
        puts "  Status: #{site_status['status']}"
        puts "  Hash: #{site_status['hash'][0..8]}..."
        
      rescue => e
        puts "  Error: #{e.message}"
        error_status = create_error_status(site, e.message)
        updated_sites << error_status
      end
    end
    
    # Update status file
    new_status = {
      'last_updated' => Time.now.utc.iso8601,
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

  def check_site(site, current_status, history)
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
    
    # Return updated site status
    {
      'id' => site['id'],
      'name' => site['name'],
      'url' => site['url'],
      'status' => status,
      'last_check' => Time.now.utc.iso8601,
      'last_change' => change_detected ? Time.now.utc.iso8601 : (previous_site&.dig('last_change')),
      'hash' => new_hash,
      'error' => nil
    }
  end

  def fetch_web_content(url)
    uri = URI(url)
    
    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
      http.open_timeout = 10
      http.read_timeout = 30
      
      request = Net::HTTP::Get.new(uri)
      request['User-Agent'] = 'WebMonitor/1.0'
      
      response = http.request(request)
      
      unless response.code.to_i.between?(200, 299)
        raise "HTTP #{response.code}: #{response.message}"
      end
      
      response.body
    end
  end

  def extract_content(html, selector, exclude_selectors = [])
    doc = Nokogiri::HTML(html)
    
    # Extract target content
    target = doc.css(selector)
    return '' if target.empty?
    
    # Remove excluded elements
    exclude_selectors.each do |exclude_sel|
      target.css(exclude_sel).remove
    end
    
    # Get text content and normalize
    content = target.text.strip
    
    # Normalize whitespace and remove dynamic content
    content = content.gsub(/\s+/, ' ')  # Multiple spaces to single space
                   .gsub(/\d{4}-\d{2}-\d{2}/, '')  # Remove dates
                   .gsub(/\d{1,2}:\d{2}(:\d{2})?/, '')  # Remove times
                   .gsub(/\b\d+\s*(views?|comments?|likes?)\b/i, '')  # Remove counters
                   .gsub(/\s+/, ' ')  # Clean up spaces again
                   .strip
    
    content
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
end

# Run the monitor if called directly
if __FILE__ == $0
  monitor = WebMonitor.new
  monitor.run
end