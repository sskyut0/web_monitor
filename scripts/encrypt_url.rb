#!/usr/bin/env ruby
# frozen_string_literal: true

require 'openssl'
require 'base64'
require 'digest'

# URL Encryption Utility
class URLEncryption
  def initialize(key = nil)
    @encryption_key = key || ENV['MONITOR_ENCRYPTION_KEY'] || 'default-key-change-in-production'
  end

  def encrypt(url)
    cipher = OpenSSL::Cipher.new('aes-256-cbc')
    cipher.encrypt
    key = Digest::SHA256.digest(@encryption_key)
    cipher.key = key
    iv = cipher.random_iv

    encrypted = cipher.update(url) + cipher.final
    Base64.encode64(iv + encrypted).strip
  end

  def decrypt(encrypted_data)
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

# Command line usage
if __FILE__ == $PROGRAM_NAME
  if ARGV.length < 2
    puts 'Usage: ruby encrypt_url.rb [encrypt|decrypt] <url_or_encrypted_data>'
    puts ''
    puts 'Examples:'
    puts '  ruby encrypt_url.rb encrypt https://example.com'
    puts '  ruby encrypt_url.rb decrypt <encrypted_string>'
    puts ''
    puts 'Environment variables:'
    puts '  MONITOR_ENCRYPTION_KEY - Custom encryption key (optional)'
    exit 1
  end

  action = ARGV[0]
  data = ARGV[1]

  encryptor = URLEncryption.new

  case action
  when 'encrypt'
    encrypted = encryptor.encrypt(data)
    puts "Original URL: #{data}"
    puts "Encrypted: #{encrypted}"
    puts ''
    puts 'Add to sites.json as:'
    puts '{'
    puts '  "id": "site_id",'
    puts '  "name": "Site Name",'
    puts "  \"url\": \"#{encrypted}\","
    puts '  "encrypted": true,'
    puts '  "selector": "main",'
    puts '  "exclude_selectors": [],'
    puts '  "description": "Description"'
    puts '}'
  when 'decrypt'
    begin
      decrypted = encryptor.decrypt(data)
      puts "Encrypted: #{data}"
      puts "Decrypted URL: #{decrypted}"
    rescue StandardError => e
      puts "Error decrypting: #{e.message}"
      exit 1
    end
  else
    puts "Invalid action. Use 'encrypt' or 'decrypt'"
    exit 1
  end
end
