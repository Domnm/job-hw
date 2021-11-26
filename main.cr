require "http"
require "csv"
require "lexbor"

# TODO: Tests
# TODO: Each page could be loaded and proccessed concurrently

dept_iata = "NBO"
dest_iata = "MBA"
currency = "USD" # "KES"

# Will be needed later to store all the collected data
alias DataType = Hash(String, String | Float64 | Int32 | Time | Nil)
data = Array(DataType).new

offsets = 10..20

offsets.each do |offset|
    out_time = Time.utc() + offset.days
    in_time = out_time + 7.days

    # construct an url which deals to flight list page
    p url = "https://www.fly540.com/flights/?isoneway=0&depairportcode=#{dept_iata}&arrvairportcode=#{dest_iata}&date_from=#{out_time.to_s("%a%2C+%d+%b+%Y")}&date_to=#{in_time.to_s("%a%2C+%d+%b+%Y")}&adult_no=1&children_no=0&infant_no=0&currency=#{currency}&searchFlight="

    flight_list_page = HTTP::Client.get url


    # Page parsing
    if (flight_list_page)
      flight_list_page = Lexbor::Parser.new(flight_list_page.body).body.not_nil!
    else
      raise "Failed to get the flight list page"
    end

    # these are short 5-digit ids
    outbound_request_id = flight_list_page.css("input[id=outbound_request_id]").to_a[0]["value"]
    inbound_request_id = flight_list_page.css("input[id=inbound_request_id]").to_a[0]["value"]

    # gets parts of pages neccesesary to find all the required ids
    flight_depart_page = flight_list_page.css("#book-form > div.fly5-flights.fly5-depart.th > div.fly5-results")
    flight_return_page = flight_list_page.css("#book-form > div.fly5-flights.fly5-return.th > div.fly5-results")

    # finds other ids
    outbound_ids = get_ids(flight_depart_page)
    inbound_ids = get_ids(flight_return_page)

    outbound_ids.each do |outbound_id|
      inbound_ids.each do |inbound_id|
        p url = "https://www.fly540.com/flights/index.php?&task=airbook.addPassengers&outbound_request_id=#{outbound_request_id}&inbound_request_id=#{inbound_request_id}&outbound_solution_id=#{outbound_id["solution_id"].gsub("=") {"%3D"}}&outbound_cabin_class=#{outbound_id["class_id"]}&inbound_solution_id=#{inbound_id["solution_id"].
      gsub("=") {"%3D"}}&inbound_cabin_class=#{inbound_id["class_id"]}&adults=1&children=0&infants=0&change_flight="

        response = HTTP::Client.get(url)

        p url = "https://www.fly540.com" + response.headers["Location"]

        data << get_info(url, out_time.year, in_time.year)
      end
    end

end

# Creates a CSV file
result = CSV.build(seperator = ';') do |csv|
  csv.row "outbound_departure_airport", "outbound_arrival_airport",
    "outbound_departure_time", "outbound_arrival_time",
    "inbound_departure_airport", "inbound_arrival_airport",
    "inbound_departure_time", "inbound_arrival_time",
    "total_price", "taxes"

  data.each do |info|
    csv.row info["outbound_departure_airport"],
      info["outbound_arrival_airport"],
      info["outbound_departure_time"],
      info["outbound_arrival_time"],
      info["inbound_departure_airport"],
      info["inbound_arrival_airport"],
      info["inbound_departure_time"],
      info["inbound_arrival_time"],
      info["total_price"],
      info["taxes"]
  end
end

File.write("data.csv", result)

def get_info(url, out_year, in_year, location = "Africa/Nairobi")
  flight_info_page = HTTP::Client.get(url)

  if (flight_info_page)
    flight_info_page = Lexbor::Parser.new(flight_info_page.body).body.not_nil!
  else
    raise "Failed to get the flight information page"
  end

  info = DataType.new
  time_parse = "%Y%a %d, %b %H:%M%p"
  time_display = "%a %b %d %T GMT %Y"

  # Gets outbound_departure_airport and outbound_arrival_airport
  info["outbound_departure_airport"] = flight_info_page.css("#fsummary > div.fly5-fldet.fly5-fout > div.row.row-eq-height.fly5-liner > div.col-4.fly5-frshort").first.inner_text[1..3]
  info["outbound_arrival_airport"] = flight_info_page.css("#fsummary > div.fly5-fldet.fly5-fout > div.row.row-eq-height.fly5-liner > div.col-4.fly5-toshort").first.inner_text[1..3]

  # Gets outbound_departure_time
  time_str = out_year.to_s + flight_info_page.css("#fsummary > div.fly5-fldet.fly5-fout > div.row.row-eq-height.fly5-det > div.col-5.fly5-timeout > span.fly5-fdate").first.inner_text +
  flight_info_page.css("#fsummary > div.fly5-fldet.fly5-fout > div.row.row-eq-height.fly5-det > div.col-5.fly5-timeout > span.fly5-ftime").first.inner_text
  info["outbound_departure_time"] = Time.parse(time_str, time_parse, Time::Location.load(location)).to_utc.to_s(time_display)

  # Gets outbound_arrival_time
  time_str = out_year.to_s + flight_info_page.css("#fsummary > div.fly5-fldet.fly5-fout > div.row.row-eq-height.fly5-det > div.col-5.fly5-timein > span.fly5-fdate").first.inner_text +
  flight_info_page.css("#fsummary > div.fly5-fldet.fly5-fout > div.row.row-eq-height.fly5-det > div.col-5.fly5-timein > span.fly5-ftime").first.inner_text
  info["outbound_arrival_time"] = Time.parse(time_str, time_parse, Time::Location.load(location)).to_utc.to_s(time_display)


  #  Get inbound
  info["inbound_departure_airport"] = flight_info_page.css("#fsummary > div:nth-child(2) > div.row.row-eq-height.fly5-liner > div.col-4.fly5-frshort").first.inner_text[1..3]
  info["inbound_arrival_airport"] = flight_info_page.css("#fsummary > div:nth-child(2) > div.row.row-eq-height.fly5-liner > div.col-4.fly5-toshort").first.inner_text[1..3]

  # Gets inbound_departure_airport
  time_str = in_year.to_s + flight_info_page.css("#fsummary > div:nth-child(2) > div.row.row-eq-height.fly5-det > div.col-5.fly5-timeout > span.fly5-fdate").first.inner_text +
  flight_info_page.css("#fsummary > div:nth-child(2) > div.row.row-eq-height.fly5-det > div.col-5.fly5-timeout > span.fly5-ftime").first.inner_text
  info["inbound_departure_time"] = Time.parse(time_str, time_parse, Time::Location.load(location)).to_utc.to_s(time_display)

  # Gets inbound_arrival_airport
  time_str = in_year.to_s + flight_info_page.css("#fsummary > div:nth-child(2) > div.row.row-eq-height.fly5-det > div.col-5.fly5-timein > span.fly5-fdate").first.inner_text +
  flight_info_page.css("#fsummary > div:nth-child(2) > div.row.row-eq-height.fly5-det > div.col-5.fly5-timein > span.fly5-ftime").first.inner_text
  info["inbound_arrival_time"] = Time.parse(time_str, time_parse, Time::Location.load(location)).to_utc.to_s(time_display)


  # gets tax info
  tax = 0
  flight_info_page.css("#breakdown > div > div:nth-child(1) > div:nth-child(4) > span").each do |t|
    tax += t.inner_text.to_f
  end
  flight_info_page.css("#breakdown > div > div:nth-child(2) > div:nth-child(4) > span").each do |t|
    tax += t.inner_text.to_f
  end
  info["taxes"] = tax

  # gets price info
  total_price = 0
  flight_info_page.css("#breakdown > div > div.total > strong > span").each do |t|
    total_price += t.inner_text.to_f
  end
  info["total_price"] = total_price

  info
end

# Gets [inbound | outbound]_solution_ids
# and [inbound | outbound]_cabin_classes
def get_ids (flight_depart_page)
  solution_ids = Array(String).new
  class_ids = Array(String).new

  # since an iterator is always returned with .css even if one element is found
  # it is neccesesary to iterate other that
  flight_depart_page.each do |flights|
    # iterates over all possible flights
    flights.children.each do |flight|

      # finds solution_id (unique for each flight)
      flight.css(".flight-classes").each do |id|
        solution_ids << id["data-flight-key"]
      end

      # finds the cabin_class
      flight.css("div div div div div span.greyed, button").each_with_index do |cab_class, ix|
        # This happens then tickets of that class are sold out
        if cab_class["class"] == "greyed"
          next
        else
          class_ids << ix.to_s
          break
        end
      end

    end
  end

  # Ultimately not necessary, but puts data in a easer to comprehend way
  # Each element of this array has needed ids
  ret = Array(Hash(String, String)).new
  solution_ids.each_with_index do |solution_id, ix|
    ret << {"solution_id" => solution_id, "class_id" => class_ids[ix]}
  end

  ret
end
