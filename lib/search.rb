require 'faraday'
require 'faraday_middleware'
require 'pathname'
require 'yaml'
require 'simple_oauth'
require 'csv'
require 'open-uri'
require 'nokogiri'

module Fracking
  class Search
    CONFIG_DIR = Pathname.new(File.expand_path(File.join(File.dirname(__FILE__), '../config')))
    OUTPUT_PATH = Pathname.new(File.expand_path(File.join(File.dirname(__FILE__), '../output')))
    
    def initialize
      if !File.exists?(OUTPUT_PATH)
        Dir.mkdir(OUTPUT_PATH)
      end
      
      parse = lambda {|text| text.split("\n").select {|line| line !~ /^\s*$/}.map(&:strip)}
      
      
      @document_types = parse.call(File.read(CONFIG_DIR.join('./document_filetypes.txt')))
      @domains = parse.call(File.read(CONFIG_DIR.join('./domains.txt')))
      
      @domains = @domains.map {|domain| domain.gsub(/^http(s)?:\/\//,'')}
      
      @search_terms = parse.call(File.read(CONFIG_DIR.join('./search_terms.txt')))
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
      output_path = File.expand_path(OUTPUT_PATH.join("docs.csv"))
      
      @urls_already_hit = []
      
      if File.exists?(output_path)
        CSV.foreach(output_path, :headers => true) do |row|
          @urls_already_hit << row['url']
        end
      end
      
      @urls_already_hit = @urls_already_hit.uniq
      
      @document_types.each do |type|
        @domains.each do |domain|
          @search_terms.each do |term|
            request(type, domain, term)
          end
        end
      end
      
      save_files!
    end
    
    def save_files!
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
      html_directory = directory.join("./html")
      if !File.exists?(directory)
        Dir.mkdir(directory)
        Dir.mkdir(html_directory)
      end
      
      
      html = ['', '.html', '.htm'].include?(File.extname(row['url']).downcase)

      if html
        output_path = html_directory.join(File.basename(row['url'], File.extname(row['url'])) + '.html')
      else
        output_path = directory.join(File.basename(row['url']))
      end
      
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
      return if web_response['count'].to_i == 0
      
      output = File.expand_path(OUTPUT_PATH.join("./docs.csv"))
      if !File.exists?(output)
        File.open(output, "w") {|f| f.write("date,url,title,abstract,filetype,site,terms,linking_page\n") }
      end
      # headers are "date,url,title,abstract"
      CSV.open(output, "a") do |csv|
        Array(web_response['results']).each do |entry|
          if options['filetype'] == 'html'
            doc = Nokogiri::HTML.parse(open(entry['url']))
            tags = doc.xpath("//a").select {|a| a.attr('href') =~ /\.(pdf|doc|docx|xls|xlsx|ppt|pptx)$/}
            tags.each do |t|
              uri = URI.parse(URI.escape(t.attr('href')))
              uri.host = URI.parse(entry['url']).host if uri.host.nil?
              uri.scheme = URI.parse(entry['url']).scheme if uri.scheme.nil?
              
              next if @urls_already_hit.include?(uri.to_s)
              
              @urls_already_hit << uri.to_s
              csv << [
                entry['date'],
                uri.to_s,
                t.inner_text,
                t.attr('title'),
                options['filetype'],
                options['site'],
                options['term'],
                entry['url']
              ]

            end
          else
            if @urls_already_hit.include?(entry['url'])
              puts "Skipping url #{entry['url']}"
              next
            else
              @urls_already_hit << entry['url']
            end
            
            
            csv << [
              entry['date'],
              entry['url'],
              entry['title'],
              entry['abstract'],
              options['filetype'],
              options['site'],
              options['term'],
              ''
            ]
          end
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