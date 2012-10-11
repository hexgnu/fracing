require 'faraday'
require 'faraday_middleware'
require 'pathname'
require 'yaml'
require 'simple_oauth'
require 'csv'
require 'open-uri'

module Fracking
  class Search
    CONFIG_DIR = Pathname.new(File.join(File.dirname(__FILE__), '../config'))
    OUTPUT_PATH = Pathname.new(File.join(File.dirname(__FILE__), '../output'))
    
    def initialize
      if !File.exists?(OUTPUT_PATH)
        Dir.mkdir(OUTPUT_PATH)
      end
      @document_types = File.read(CONFIG_DIR.join('./document_filetypes.txt')).split("\n")
      @domains = File.read(CONFIG_DIR.join('./domains.txt')).split("\n")
      @search_terms = File.read(CONFIG_DIR.join('./search_terms.txt')).split("\n")
      @yahoo_api = YAML::load_file(CONFIG_DIR.join('./yahoo_api.yml'))
      @search_type = "limitedweb"
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
    
    def request_and_save(filetype, term_search, site, start)
      puts "Searching for #{term_search} on #{site} starting_at #{start}"
      response = connection.get(@search_type, :type => filetype, :q => "#{term_search}+site:#{site}", :start => start)
      save_response(response, 'filetype' => filetype, 'site' => site, 'term' => term_search)
    end
    
    def request(filetype, site, term)
      #term_search = terms.map {|term| term.split(/\s+/).join('|') }.join('+')
      term_search = term.gsub(/\s+/, '+')
      start = 0
      begin
        start = request_and_save(filetype, term_search, site, start)
      end until start.nil?
    end
    
    def execute!
      if !File.exists?(OUTPUT_PATH.join("./docs.csv"))
        @document_types.each do |type|
          @domains.each do |domain|
            @search_terms.each do |term|
              request(type, domain, term)
            end
          end
        end
      end
      
      thread_pool = []
      CSV.foreach(OUTPUT_PATH.join("./docs.csv"), :headers => true) do |row|
        until thread_pool.select(&:alive?).length <= 4
          sleep 0.01
        end
        thread_pool << Thread.new(row) do |local_row|
          save_row(local_row)
        end
      end
      thread_pool.each {|thr| thr.join }
    end
    
    def save_row(row)
      directory = OUTPUT_PATH.join("./#{row['site']}")
      if !File.exists?(directory)
        Dir.mkdir(directory)
      end
      output_path = directory.join(File.basename(row['url']))
      return if File.exists?(output_path)
      File.open(output_path, 'wb') do |f|
        open(row['url']) do |remote_file|
          f.write(remote_file.read)
        end
      end
      puts "SUCCESS: Downloaded #{row['url']}"
    rescue Exception => e
      puts e.message
    end
    
    # returns the next page to go to or nil if no more pages to go to
    def save_response(response, options)
      web_response = response.body.fetch('bossresponse').fetch(@search_type)
      total = web_response['totalresults'].to_i
      last_count = web_response['start'].to_i + web_response['count'].to_i
      
      output = OUTPUT_PATH.join("./docs.csv")
      if !File.exists?(output)
        File.open(output, "w") {|f| f.write("date,url,title,abstract,filetype,site,terms\n") }
      end
      # headers are "date,url,title,abstract"
      
      CSV.open(output, "a") do |csv|
        Array(web_response['results']).each do |entry|
          csv << [
            entry['date'],
            entry['url'],
            entry['title'],
            entry['abstract'],
            options['filetype'],
            options['site'],
            options['term']
          ]
        end
      end
      
      if total <= last_count
        nil
      else
        last_count + 1
      end
    end
    

  end
end