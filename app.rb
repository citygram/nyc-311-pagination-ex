require 'active_support/time'
require 'json'
require 'faraday'
require 'sinatra'

configure do
  set :ceiling, 5000
  set :target_host, 'https://data.cityofnewyork.us'
  set :time_zone, ActiveSupport::TimeZone["Eastern Time (US & Canada)"]
end

helpers do
  def build_url(host, path, params)
    url = URI.parse(host)
    url.path = path
    url.query = Faraday::Utils.build_query(params.select { |k,_| k.start_with?('$') })
    url.to_s
  end

  def build_next_page_params(params)
    params = params.dup
    params['$limit'] = Integer(params['$limit'] || 1000)
    params['$offset'] = Integer(params['$offset'] || 0)
    params['$offset'] += params['$limit']
    params
  end
end

get '*' do
  connection = Faraday.new(url: build_url(settings.target_host, request.path, params))
  response = connection.get

  collection = JSON.parse(response.body)

  features = collection.map do |item|
    time = Time.iso8601(item['created_date']).in_time_zone(settings.time_zone)

    city = item['city']
    title =
      case item['address_type']
      when 'ADDRESS'
        "#{time.strftime("%m/%d  %I:%M %p")} - A new 311 case has been opened at #{item['incident_address'].titleize} in #{city.capitalize}."
      when 'INTERSECTION'
        intersection_street_1 = item['intersection_street_1']
        intersection_street_2 = item['intersection_street_2']
        "#{time.strftime("%m/%d  %I:%M %p")} - A new 311 case has been opened at the intersection of #{intersection_street_1.titleize} and #{intersection_street_2.titleize} in #{city.capitalize}."
      when 'BLOCKFACE'
        cross_street_1 = item['cross_street_1']
        cross_street_2 = item['cross_street_2']
        street = item['street_name']
        "#{time.strftime("%m/%d  %I:%M %p")} - A new 311 case has been opened on #{street.titleize}, between #{cross_street_1.titleize} and #{cross_street_2.titleize} in #{city.capitalize}."
      else
        "#{time.strftime("%m/%d  %I:%M %p")} - A new 311 case has been opened on #{item['street_name']} in #{city}."
      end

    title << " The complaint type is #{item['complaint_type'].downcase} - #{item['descriptor']} and the assigned agency is #{item['agency']}"

    { 'id' => item['unique_key'],
      'type' => 'Feature',
      'properties' => item.merge('title' => title),
      'geometry' => {
        'type' => 'Point',
        'coordinates' => [
          item['longitude'].to_f,
          item['latitude'].to_f ] } }
  end

  content_type :json

  next_page_params = build_next_page_params(params)
  next_page = build_url(request.base_url, request.path, next_page_params)

  if (next_page_params['$offset'] + next_page_params['$limit']) <= settings.ceiling
    headers 'Next-Page' => next_page
  end

  JSON.pretty_generate('type' => 'FeatureCollection', 'features' => features)
end
