fracing
=======

Fracing script for CU denver


Setup
=======
1. Install ruby 1.9.x from either installing rvm (https://rvm.io/rvm/install/) on a unix based machine or using ruby installer (http://rubyinstaller.org/).

2. download the repository from https://github.com/hexgnu/fracing and remember where you saved it

3. make sure that you have bundler installed in your ruby version by running `gem install bundler`

4. change directories into the folder where you saved the github repo. Then run `bundle install` (this will install a bunch of gems that are needed)



Configuration
========

1. You will need to have a yahoo api key to run this script using their BOSS service.  This cost 80 cents for every 1000 queries you make against them.  So it is useful and quite cost effective. To do this manually edit the file in 'config/yahoo_api.yml'

2. There will be a file with a list of sites to crawl this is called 'config/domains.txt'. Just put in the site domain newline delimited

3. There will be a file called 'config/search_terms.txt'.  In here put a new line delimited version of all the search terms you want to use.  These will be 'OR' terms meaning that you will search for any of these matches.

Running
========

The easiest way to run this is to type in the root folder of the repo `ruby script/run.rb`

