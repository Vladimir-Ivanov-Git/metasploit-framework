# -*- coding: binary -*-
require 'rex/proto/kerberos'

module Msf
  module Kerberos
    module Client
      module TgsRequest

        # Builds the encrypted Kerberos TGS request
        #
        # @param opts [Hash{Symbol => <Rex::Proto::Kerberos::Model::Element>}]
        # @option opts [Rex::Proto::Kerberos::Model::AuthorizationData] :auth_data
        # @option opts [Rex::Proto::Kerberos::Model::EncryptedData] :enc_auth_data
        # @option opts [Rex::Proto::Kerberos::Model::EncryptionKey] :subkey
        # @option opts [Rex::Proto::Kerberos::Model::Checksum] :checksum
        # @option opts [Rex::Proto::Kerberos::Model::Authenticator] :auhtenticator
        # @option opts [Array<Rex::Proto::Kerberos::Model::PreAuthData>] :pa_data
        # @return [Rex::Proto::Kerberos::Model::KdcRequest]
        # @raise [RuntimeError] if ticket isn't available
        # @see Rex::Proto::Kerberos::Model::AuthorizationData
        # @see Rex::Proto::Kerberos::Model::EncryptedData
        # @see Rex::Proto::Kerberos::Model::EncryptionKey
        # @see Rex::Proto::Kerberos::Model::Checksum
        # @see Rex::Proto::Kerberos::Model::Authenticator
        # @see Rex::Proto::Kerberos::Model::PreAuthData
        # @see Rex::Proto::Kerberos::Model::KdcRequest
        def build_tgs_request(opts = {})
          subkey = opts[:subkey] || build_subkey(opts)

          if opts[:enc_auth_data]
            enc_auth_data = opts[:enc_auth_data]
          elsif opts[:auth_data]
            enc_auth_data = build_enc_auth_data(
              auth_data: opts[:auth_data],
              subkey: subkey
            )
          else
            enc_auth_data = nil
          end

          body = build_tgs_request_body(opts.merge(
            enc_auth_data: enc_auth_data
          ))

          checksum = opts[:checksum] || build_tgs_body_checksum(:body => body)

          if opts[:auhtenticator]
            authenticator = opts[:authenticator]
          else
            authenticator = build_authenticator(opts.merge(
              subkey: subkey,
              checksum: checksum
            ))
          end

          if opts[:ap_req]
            ap_req = opts[:ap_req]
          else
            ap_req = build_ap_req(opts.merge(:authenticator => authenticator))
          end

          pa_ap_req = Rex::Proto::Kerberos::Model::PreAuthData.new(
            type: Rex::Proto::Kerberos::Model::PA_TGS_REQ,
            value: ap_req.encode
          )

          pa_data = []
          pa_data.push(pa_ap_req)
          if opts[:pa_data]
            opts[:pa_data].each { |pa| pa_data.push(pa) }
          end

          request = Rex::Proto::Kerberos::Model::KdcRequest.new(
            pvno: 5,
            msg_type: Rex::Proto::Kerberos::Model::TGS_REQ,
            pa_data: pa_data,
            req_body: body
          )

          request
        end

        # Builds the encrypted TGS authorization data
        #
        # @param opts [Hash{Symbol => <Rex::Proto::Kerberos::Model::AuthorizationData, Rex::Proto::Kerberos::Model::EncryptionKey>}]
        # @option opts [Rex::Proto::Kerberos::Model::AuthorizationData] :auth_data
        # @option opts [Rex::Proto::Kerberos::Model::EncryptionKey] :subkey
        # @return [Rex::Proto::Kerberos::Model::EncryptedData]
        # @raise [RuntimeError] if auth_data option isn't provided
        # @see Rex::Proto::Kerberos::Model::AuthorizationData
        # @see Rex::Proto::Kerberos::Model::EncryptionKey
        # @see Rex::Proto::Kerberos::Model::EncryptedData
        def build_enc_auth_data(opts = {})
          auth_data = opts[:auth_data]

          if auth_data.nil?
            raise ::RuntimeError, 'auth_data option required on #build_enc_auth_data'
          end

          subkey = opts[:subkey] || build_subkey(opts)

          encrypted = auth_data.encrypt(subkey.type, subkey.value)

          e_data = Rex::Proto::Kerberos::Model::EncryptedData.new(
            etype: subkey.type,
            cipher: encrypted
          )

          e_data
        end

        # Builds a KRB_AP_REQ message
        #
        # @param opts [Hash{Symbol => <Fixnum, Rex::Proto::Kerberos::Model::Ticket, Rex::Proto::Kerberos::Model::EncryptedData, Rex::Proto::Kerberos::Model::EncryptionKey>}]
        # @option opts [Fixnum] :pvno
        # @option opts [Fixnum] :msg_type
        # @option opts [Fixnum] :ap_req_options
        # @option opts [Rex::Proto::Kerberos::Model::Ticket] :ticket
        # @option opts [Rex::Proto::Kerberos::Model::EncryptedData] :authenticator
        # @option opts [Rex::Proto::Kerberos::Model::EncryptionKey] :session_key
        # @return [Rex::Proto::Kerberos::Model::EncryptionKey]
        # @raise [RuntimeError] if ticket option isn't provided
        # @see Rex::Proto::Kerberos::Model::Ticket
        # @see Rex::Proto::Kerberos::Model::EncryptedData
        # @see Rex::Proto::Kerberos::Model::EncryptionKey
        def build_ap_req(opts = {})
          pvno = opts[:pvno] || Rex::Proto::Kerberos::Model::VERSION
          msg_type = opts[:msg_type] || Rex::Proto::Kerberos::Model::AP_REQ
          options = opts[:ap_req_options] || 0
          ticket = opts[:ticket]
          authenticator = opts[:authenticator] || build_authenticator(opts)
          session_key = opts[:session_key] || build_subkey(opts)

          if ticket.nil?
            raise ::RuntimeError, 'Building a AP-REQ without ticket not supported'
          end

          enc_authenticator = Rex::Proto::Kerberos::Model::EncryptedData.new(
            etype: session_key.type,
            cipher: authenticator.encrypt(session_key.type, session_key.value)
          )

          ap_req = Rex::Proto::Kerberos::Model::ApReq.new(
            pvno: pvno,
            msg_type: msg_type,
            options: options,
            ticket: ticket,
            authenticator: enc_authenticator
          )

          ap_req
        end

        # Builds a kerberos authenticator for a TGS request
        #
        # @param opts [Hash{Symbol => <Rex::Proto::Kerberos::Model::PrincipalName, String, Time, Rex::Proto::Kerberos::Model::EncryptionKey>}]
        # @option opts [Rex::Proto::Kerberos::Model::PrincipalName] :cname
        # @option opts [String] :realm
        # @option opts [Time] :ctime
        # @option opts [Fixnum] :cusec
        # @option opts [Rex::Proto::Kerberos::Model::Checksum] :checksum
        # @option opts [Rex::Proto::Kerberos::Model::EncryptionKey] :subkey
        # @return [Rex::Proto::Kerberos::Model::Authenticator]
        # @see Rex::Proto::Kerberos::Model::PrincipalName
        # @see Rex::Proto::Kerberos::Model::Checksum
        # @see Rex::Proto::Kerberos::Model::EncryptionKey
        # @see Rex::Proto::Kerberos::Model::Authenticator
        def build_authenticator(opts = {})
          cname = opts[:cname] || build_client_name(opts)
          realm = opts[:realm] || ''
          ctime = opts[:ctime] || Time.now
          cusec = opts[:cusec] || ctime.usec
          checksum = opts[:checksum] || build_tgs_body_checksum(opts)
          subkey = opts[:subkey] || build_subkey(opts)

          authenticator = Rex::Proto::Kerberos::Model::Authenticator.new(
            vno: 5,
            crealm: realm,
            cname: cname,
            checksum: checksum,
            cusec: cusec,
            ctime: ctime,
            subkey: subkey
          )

          authenticator
        end

        # Builds an encryption key to protect the data sent in the TGS request.
        #
        # @param opts [Hash{Symbol => <Fixnum, String>}]
        # @option opts [Fixnum] :subkey_type
        # @option opts [String] :subkey_value
        # @return [Rex::Proto::Kerberos::Model::EncryptionKey]
        # @see Rex::Proto::Kerberos::Model::EncryptionKey
        def build_subkey(opts={})
          subkey_type = opts[:subkey_type] || 23
          subkey_value = opts[:subkey_value] || "AAAABBBBCCCCDDDD" #Rex::Text.rand_text(16)

          subkey = Rex::Proto::Kerberos::Model::EncryptionKey.new(
            type: subkey_type,
            value: subkey_value
          )

          subkey
        end


        # Builds a kerberos TGS request body
        #
        # @param opts [Hash{Symbol => <Fixnum, Time, String, Rex::Proto::Kerberos::Model::PrincipalName, Rex::Proto::Kerberos::Model::EncryptedData>}]
        # @option opts [Fixnum] :options
        # @option opts [Time] :from
        # @option opts [Time] :till
        # @option opts [Time] :rtime
        # @option opts [Fixnum] :nonce
        # @option opts [Fixnum] :etype
        # @option opts [Rex::Proto::Kerberos::Model::PrincipalName] :cname
        # @option opts [String] :realm
        # @option opts [Rex::Proto::Kerberos::Model::PrincipalName] :sname
        # @option opts [Rex::Proto::Kerberos::Model::EncryptedData] :enc_auth_data
        # @return [Rex::Proto::Kerberos::Model::KdcRequestBody]
        # @see Rex::Proto::Kerberos::Model::PrincipalName
        # @see Rex::Proto::Kerberos::Model::KdcRequestBody
        def build_tgs_request_body(opts = {})
          options = opts[:options] || 0x50800000 # Forwardable, Proxiable, Renewable
          from = opts[:from] || Time.utc('1970-01-01-01 00:00:00')
          till = opts[:till] || Time.utc('1970-01-01-01 00:00:00')
          rtime = opts[:rtime] || Time.utc('1970-01-01-01 00:00:00')
          nonce = opts[:nonce] || Rex::Text.rand_text_numeric(6).to_i
          etype = opts[:etype] || [Rex::Proto::Kerberos::Model::KERB_ETYPE_RC4_HMAC]
          cname = opts[:cname] || build_client_name(opts)
          realm = opts[:realm] || ''
          sname = opts[:sname] || build_server_name(opts)
          enc_auth_data = opts[:enc_auth_data] || nil

          body = Rex::Proto::Kerberos::Model::KdcRequestBody.new(
            options: options,
            cname: cname,
            realm: realm,
            sname: sname,
            from: from,
            till: till,
            rtime: rtime,
            nonce: nonce,
            etype: etype,
            enc_auth_data: enc_auth_data
          )

          body
        end

        # Builds a Kerberos TGS Request body checksum
        #
        # @param opts [Hash{Symbol => <Rex::Proto::Kerberos::Model::KdcRequestBody, Fixnum>}]
        # @option opts [Rex::Proto::Kerberos::Model::KdcRequestBody] :body
        # @return [Rex::Proto::Kerberos::Model::Checksum]
        # @see #build_tgs_request_body
        # @see Rex::Proto::Kerberos::Model::Checksum
        def build_tgs_body_checksum(opts = {})
          body = opts[:body] || build_tgs_request_body(opts)
          checksum_body = body.checksum(7)
          checksum = Rex::Proto::Kerberos::Model::Checksum.new(
            type: 7,
            checksum: checksum_body
          )

          checksum
        end
      end
    end
  end
end
