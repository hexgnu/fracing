require 'faraday'
require 'faraday_middleware'
require 'pathname'
require 'yaml'
require 'simple_oauth'
require 'csv'

module Fracking
  class Search
    CONFIG_DIR = Pathname.new(File.join(File.dirname(__FILE__), '../config'))
    OUTPUT_PATH = Pathname.new(File.join(File.dirname(__FILE__), '../output'))
    
    def initialize
      @document_types = File.read(CONFIG_DIR.join('./document_filetypes.txt')).split("\n")
      @domains = File.read(CONFIG_DIR.join('./domains.txt')).split("\n")
      @search_terms = File.read(CONFIG_DIR.join('./search_terms.txt')).split("\n")
      @yahoo_api = YAML::load_file(CONFIG_DIR.join('./yahoo_api.yml'))
    end
    
    def connection
      @connection ||= Faraday.new 'http://yboss.yahooapis.com/ysearch' do |conn|
        conn.request :oauth, :consumer_key => @yahoo_api['consumer_key'], :consumer_secret => @yahoo_api['consumer_secret']
        conn.request :json

        conn.response :xml,  :content_type => /\bxml$/
        conn.response :json, :content_type => /\bjson$/

        conn.use :instrumentation
        conn.adapter Faraday.default_adapter
      end
    end
    
    
    def request(filetype, site, terms)
      term_search = terms.map {|t| "\"#{term}\"" }.join(' ')
      
      response = connection.get("web", :q => "filetype:#{filetype} site:#{site} #{term_search}")
      
      next_page_start = save_response(response)
      
      until next_page_start.nil?
        response = connection.get("web", :q => "filetype:#{filetype} site:#{site} \"#{term}\"", :start => next_page_start)
        next_page_start = save_response(response)
      end
    end
    
    def execute!
      @document_types.each do |type|
        @domains.each do |domain|
          request(type, domain, @search_terms)
        end
      end
    end
    
    # returns the next page to go to or nil if no more pages to go to
    def save_response(response)
      web_response = response.body.fetch('bossresponse').fetch('web')
      total = web_response['totalresults'].to_i
      last_count = web_response['start'].to_i + web_response['count'].to_i
      
      # headers are "date,url,title,abstract"
      
      CSV.open(OUTPUT_PATH.join("./docs.csv"), "a") do |csv|
        web_response['results'].each do |entry|
          csv << [
            entry['date'],
            entry['url'],
            entry['title'],
            entry['abstract']
          ]
        end
      end
      
      if total <= last_count
        nil
      else
        last_count + 1
      end
    rescue Exception => e
      puts e.message
    end
    

  end
end