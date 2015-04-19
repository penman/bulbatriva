require "open-uri"
require "nokogiri"
require "twitter_ebooks"
require "rest-client"

Bulbapedia = RestClient::Resource.new("http://bulbapedia.bulbagarden.net")

def Bulbapedia.go(term)
  self["w/index.php"].get params: { search: term }
end

def trivia(page)
  trivia_header_span = page.css("#Trivia").first
  return unless trivia_header_span
  siblings = trivia_header_span.parent.css("~ *")
  section_content = siblings.slice_before { |e| e.name == "h2" }.first
  lists = section_content.select { |e| %w(ol ul).include? e.name }
  items = lists.map { |e| e.css("> li") }.flatten
  items.map { |li| li.text.strip }.reject(&:empty?)
end

def already_used?(trivia)
  false
end

def trivia_from_response(response, format: "%{title} %{url}\n%{content}")
  page = Nokogiri::HTML(response.to_str)
  page.css("sup").remove
  title = page.css("#firstHeading").text
  options = trivia(page) || []
  options.map! { |option| option.split("\n").first }
  options.reject! do |option|
    format.%(title: title, content: option, url: "").length > 117 || already_used?(option)
  end
  format_args = { title: title, url: response.request.url }
  options.map { |content| format % format_args.merge(content: content) }
end

def random_trivium
  until option ||= nil
    response = Bulbapedia["wiki/Special:Random"].get
    option = trivia_from_response(response).sample
  end
  option
end

class Bulbatrivia < Ebooks::Bot
  def configure
    self.consumer_key = ENV["TWITTER_CONSUMER_KEY"]
    self.consumer_secret = ENV["TWITTER_CONSUMER_SECRET"]
    self.access_token = ENV["TWITTER_ACCESS_TOKEN"]
    self.access_token_secret = ENV["TWITTER_ACCESS_TOKEN_SECRET"]
  end

  def on_startup
    scheduler.every '1h' do
      tweet random_trivium
    end
  end

  def on_follow(user)
    follow(user.screen_name)
  end

  def on_mention(mention)
    text = meta(mention).mentionless
    text.gsub! /\A\./, ""
    response = Bulbapedia.go(text)
    if response.request.url.start_with? "http://bulbapedia.bulbagarden.net/w/index.php"
      answer = meta(mention).reply_prefix + "Bulbapedia doesn't have an article about "
      answer += answer.length + text.length > 140 ? "that" : text
      reply mention, answer
      return
    end

    options = trivia_from_response(response, format: "%{content}")
    answer = meta(mention).reply_prefix
    answer += options.sample || ""
    answer += " #{response.request.url}#Trivia" if answer.length <= 117
    answer.gsub! "  ", " "
    reply mention, answer
  end
end

Bulbatrivia.new("bulbatrivia")
