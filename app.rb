require 'json'
require 'faraday'
require 'sinatra'

get '/mobile-food-facility-permits' do
  url = URI('https://data.sfgov.org/resource/rqzj-sfat.json')
  url.query = Faraday::Utils.build_query(
    '$order' => 'approved DESC',
    '$limit' => 100,
    '$where' => "status = 'APPROVED'"+
                " AND objectid IS NOT NULL"+
                " AND latitude IS NOT NULL"+
                " AND longitude IS NOT NULL"+
                " AND approved > '#{(DateTime.now - 30).iso8601}'"
  )

  connection = Faraday.new(url: url.to_s)
  response = connection.get

  collection = JSON.parse(response.body)

  features = collection.map do |record|
    {
      'id' => record['objectid'],
      'type' => 'Feature',
      'properties' => record.merge('title' => record['fooditems']),
      'geometry' => {
        'type' => 'Point',
        'coordinates' => [
          record['longitude'].to_f,
          record['latitude'].to_f ]}}
  end

  content_type :json
  JSON.pretty_generate('type' => 'FeatureCollection', 'features' => features)
end
