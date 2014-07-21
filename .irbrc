$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), 'lib'))
require 'active_support/all'
require 'bundler/setup'
Bundler.require(:default)

puts "* Loaded Zimbra Gem"

# zimbra gem uses a SOAP library called 'handsoap', which in turn uses 'curb'
# (a ruby curl C binding library) for its HTTP client. In development and test
# environments, we do NOT want to deal with invalid SSL certificate errors, so
# for now, we monkey-patch this method.
#
# In future, we should add the cert to our computers and configure the curl
# object, like so: http://stackoverflow.com/questions/13635960/rails-curb-sslca-error-curlerrsslcacertificateerror

require 'zimbra'
require 'handsoap/http/drivers/curb_driver'

module Handsoap
  module Http
    module Drivers
      class CurbDriver
        silence_warnings do

          def send_http_request(request)
            http_client = get_curl(request.url)

            http_client.ssl_verify_peer = false # NOTE: this line is added for Planethoster

            # Set credentials. The driver will negotiate the actual scheme
            if request.username && request.password
              http_client.userpwd = [request.username, ":", request.password].join
            end
            http_client.cacert = request.trust_ca_file if request.trust_ca_file
            http_client.cert = request.client_cert_file if request.client_cert_file
            # I have submitted a patch for this to curb, but it's not yet supported. If you get errors, try upgrading curb.
            http_client.cert_key = request.client_cert_key_file if request.client_cert_key_file
            # pack headers
            headers = request.headers.inject([]) do |arr, (k,v)|
              arr + v.map {|x| "#{k}: #{x}" }
            end
            http_client.headers = headers
            # I don't think put/delete is actually supported ..
            case request.http_method
            when :get
              http_client.http_get
            when :post
              http_client.http_post(request.body)
            when :put
              http_client.http_put(request.body)
            when :delete
              http_client.http_delete
            else
              raise "Unsupported request method #{request.http_method}"
            end
            parse_http_part(http_client.header_str.gsub(/^HTTP.*\r\n/, ""), http_client.body_str, http_client.response_code, http_client.content_type)
          end

        end
      end
    end
  end
end

Zimbra.admin_api_url = ''
Zimbra.account_api_url = ''
unless Zimbra.login('', '')
  STDERR.puts "unable to login to zimbra as admin user"
end
