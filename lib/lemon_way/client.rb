require "active_support/core_ext/hash"
require 'active_support/builder'
require "httparty"


module LemonWay
  module Client
    module Base

      mattr_accessor :default_attributes

      class Error < Exception ; end

      def init(opts={})
        opts.symbolize_keys!
        self.base_uri opts.delete(:base_uri)
        self.default_attributes =  opts
      end

      def make_body(method_name, attrs={})
        options = {}
        options[:builder] = Builder::XmlMarkup.new(:indent => 2)
        options[:builder].instruct!
        options[:builder].__send__(:method_missing, method_name, xmlns: "Service") do
          default_attributes.merge(attrs).each do |key, value|
            ActiveSupport::XmlMini.to_tag(key, value, options)
          end
        end
      end

      def query(type, method, attrs={})
        response_body = send(type, "/", :body => make_body(method, attrs)) || {}
        response_body = response_body.with_indifferent_access.underscore_keys
        if response_body.has_key?("e")
          raise Error.new ["error", response_body["e"]["code"], ':', response_body["e"]["msg"], response_body["e"]["prio"]].join(' ')
        else
          if block_given?
            yield(response_body)
          else
            response_body
          end
        end
      end

      def camelize_and_ensure_keys! attrs, required_attributes=[], optional_attributes=[]
        attrs.camelize_keys!.ensure_keys required_attributes, optional_attributes 
      end

    end

    #Il est possible de créer un Wallet en marque blanche avec notre plateforme de paiement.
    #L’usage étant le cadeau commun, la liste, la cagnotte, etc.
    #La plateforme offre la possibilité de créer un compte de paiement pour les utilisateurs
    #« récolteurs » qui effectuent une liste.
    #
    #Le paiement s’effectue ensuite à partir d’utilisateurs « normaux » qui utilisent leur carte pour
    #payer le teneur de la liste (listier).
    #Le teneur de la liste peut ensuite faire un virement vers sa banque lorsque sa « récolte » est
    #terminée.
    #
    #La plateforme gère les comptes des listiers, les virements, les paiements par carte faits sur le compte du listier.
    #Le listier peut également approvisionner son propre compte avec sa carte bancaire.
    #
    #En marque blanche, Lemon Way ne fait pas de communication directe avec les clients finaux
    #(listiers ou payeurs).
    #Il est également possible de créer des comptes de type « marchand » pour les marchands favoris que vos utilisateurs payent en général, pour simplifier le paiement, avec un interfaçage spécial à prévoir chez les eMarchands (accords bi-latéraux à trouver).
    #
    #Dans la suite de ce document, l’acquéreur de la solution en marque blanche sera désigné par
    #« MARQUE BLANCHE ».
    #
    #Lemon Way met à disposition de la MARQUE BLANCHE :
    # - Un backoffice général permettant de visualiser les opérations du système et les clients
    # - Un backoffice Pro, permettant de visualiser les paiements versés à la MARQUE BLANCHE ou prélevés par LEMON WAY sur le compte de la MARQUE BLANCHE (commissions ou autre)
    # - Des webservices dans un DIRECTKIT
    # - Des pages web dans un WEBKIT
    #
    #==Prérequis
    #LEMON WAY fournit à la MARQUE BLANCHE diverses informations permettant de les
    #identifier :
    #- Un login et le mot de passe associé, permettant à la MARQUE BLANCHE de se
    #connecter au backoffice et au DIRECTKIT
    #- Un code PDV marchand, correspondant au compte marchand sur lequel la MARQUE BLANCHE recevra ses éventuelles commissions, et sur lequel LEMON WAY prélèvera ses commissions
    #- Un identifiant permettant d’utiliser le WEBKIT (le mot de passe associé est à générer sur le backoffice, par la MARQUE BLANCHE)

    module BlankLabel
      include Base
      extend self
      include HTTParty

      format :xml

      def register_wallet attrs, &block
        camelize_and_ensure_keys! attrs, %i(wallet clientMail clientTitle clientFirstName clientLastName), %i(clientTitle clientHandset)
        query :post, :RegisterWallet, attrs, &block
      end

      def get_wallet_details attrs, &block
        camelize_and_ensure_keys! attrs, %i(wallet)
        query :post, :GetWalletDetails, attrs, &block
      end

      # Crédit de wallet avec carte bancaire, sans 3D-Secure.
      # Cette méthode ne nécessite qu’un seul point d’intégration
      #
      # Avec la méthode « MoneyIn », le système effectue un rechargement du wallet par carte
      # bancaire, sans 3D-Secure :
      # * L’application MARQUE BLANCHE envoie à Lemon Way l’identifiant du wallet à créditer, l’identifiant de la carte bancaire associée au wallet, le montant à créditer, et un commentaire
      # * Lemon Way répond
      #
      # @param attrs [Hash{String, Symbol => String, Number}]
      #   - :wallet* [String] Identifiant du wallet à créditer length [0 : 256] car, ex: 33612345678 ou taxi67
      #   - :card_type* [integer] Type de carte bancaire, [1] car, can be 0 (CB), 1 (Visa) or 2 (Mastercard)
      #   - :card_number* [Number] Numéro à 16 chiffres, [16] car, ex: ￼4972000011112222
      #   - :card_crypto* [Number] Cryptogramme de la carte à 3 chiffres, [3] car, ex: 123
      #   - :card_date* [String] Date d’expiration de la carte, MM/yyyy, ex: ￼12/2013
      #   - :amount_tot* [Number] Montant à débiter de la CB, 2 décimales, ex: 15.00
      #   - :amount_com [Number] Montant que la MARQUE BLANCHE souhaite prélever, 2 décimales, ex: 1.00
      #   - :message [String] Commentaire du paiement, [0 :140] car, , ex: ￼Commande numéro 245
      #
      # @return [HashWithIndifferentAccess{key => String, Number}]
      #    - :id      [String] Identifiant de la transaction, max length 255_
      #    - :mlabel  [String] Numéro de carte masqué, ex : XXXX XXXX XXXX 9845_
      #    - :date    [String] Date de la demande, ex : 10/09/2011 18:09:27
      #    - :sen     [String] Vide dans ce cas
      #    - :rec     [String] Wallet à créditer, ex: Pizza56
      #    - :deb     [Number] 0.00 dans ce cas, ex: 0.00
      #    - :cred    [Number] Montant à créditer au wallet (total moins la commission) , ex: 15.00
      #    - :com     [Number] Commission prélevée par la MARQUE BLANCHE , ex:2.00
      #    - :msg     [Number] Commentaire ex : Commande numéro 245
      #    - :status  Non utilisé dans le kit MARQUE BLANCHE
      def money_in attrs
        camelize_and_ensure_keys! attrs, %i(wallet cardType cardNumber cardCrypto cardDate amountTot), %i(amountCom message)
        query :post, :MoneyIn, attrs do |body|
          block ? block.call(body["trans"]["hpay"]) : body["trans"]["hpay"]
        end
      end

      # Cette fonctionnalité nécessitera 3 points d’intégration par la MARQUE BLANCHE :
      # * Un appel au DIRECTKIT pour initialiser les données du rechargement de wallet Une redirection du site web de la MARQUE BLANCHE vers le WEBKIT
      # * Une page de retour sur laquelle le WEBKIT POST le résultat
      # Cinématique
      # 1. L’application MARQUE BLANCHE envoie à Lemon Way l’identifiant du wallet, un token de requête qui lui permettra de traiter la réponse du WEBKIT, et les montants
      # 2. Lemon Way retourne un token de money-in
      # 3. Le site web de la MARQUE BLANCHE redirige le CLIENT vers le WEBKIT de Lemon Way, en passant le token de money-in en paramètre GET. (Voir paragraphe 8.3.3 MoneyInWebFinalize \: finalisation de rechargement)
      #
      # @param attrs [Hash{String, Symbol => String, Number}]
      #   - :wallet* [String] Identifiant du wallet à créditer, <em>\[0 : 256] car</em>
      #   - :amount_tot* [Number] Montant à débiter de la CB <em>2 décimales</em>
      #   - :wk_token* [String]
      #     Identifiant unique de l’appel, créé par le système de la MARQUE BLANCHE, sera retourné par Lemon Way à la fin de l’opération, en POST sur l’URL de retour fournie par la MARQUE BALNCHE
      #     <em>\[1 : 10] car</em>
      #   - :return_url* [String]
      #     url de retour sur le site de la MARQUE BLANCHE, que le WEBKIT appellera pour signifier la fin de l’opération
      #     <em>\[1 : max] car</em>
      #   - :error_url* [String]
      #     url de retour sur le site de la MARQUE BLANCHE, que le WEBKIT appellera pour signaler une erreur
      #     <em>\[1 : max] car</em>
      #   - :cancel_url* [String]
      #     url de retour sur le site de la MARQUE BLANCHE, que le WEBKIT appellera en cas d’annulation de l’opération
      #     <em>\[1 : max] car</em>
      #   - :amount_com [Number] Montant que la MARQUE BLANCHE souhaite prélever <em>2 décimales</em>
      #   - :message [String] Commentaire concernant la transaction <em>\[0 :140] car</em>
      #   - :use_registered_card [Number]
      #     0 : ne pas enregistrer de carte ni utiliser de carte enregistrée
      #     1 : proposer d’utiliser une carte enregistrée ou enregistrer la
      #     <em>\[0 :1] car</em>
      # @return [String] Token de paiement à passer en GET vers l’URL du webkit
      def money_in_web_init attrs
        camelize_and_ensure_keys! attrs, %i(wallet amountTot wkToken returnUrl errorUrl cancelUrl), %i(amountCom message useRegisteredCard)
        query :post, :MoneyInWebInit, attrs do |response|
          response["moneyinweb"]["token"]
        end
      end


      # Avec la méthode  RegisterCard, le système peut envoyer une demande d’association d’une carte bancaire à un wallet :
      # - L’application MARQUE BLANCHE envoie à Lemon Way l’identifiant du wallet, ainsi que les informations sur la carte bancaire
      # - Lemon Way répond
      # @param attrs [Hash{String, Symbol => String, Number}]
      #   - :wallet* [String] Identifiant du wallet, max 256
      #   - :card_type* [String] Type de la carte. Can be 0 (CB), 1 (Visa) or 2 (Mastercard)
      #   - :card_number* [Number] Numéro de la carte, 16 chiffres
      #   - :card_code* Cryptogramme[String] de la carte, [3 : 4] car
      #   - :card_date* [String] Date d’expiration de la carte, 7 car
      # @return [String] Identifiant de la carte enregistrée
      #
      def register_card attrs
        camelize_and_ensure_keys! attrs, %i(wallet cardType cardNumber cardCode cardDate)
        query :post, :RegisterCard, attrs do |response|
          response["card"]["id"]
        end
      end


      # ==== Cinématique
      # Pour le moment, une seule carte est autorisée par wallet.
      # Avec la méthode « UnregisterCard », le système peut envoyer une demande de désactivation
      # de la carte bancaire liée à un wallet :
      # - L’application MARQUE BLANCHE envoie à Lemon Way l’identifiant du wallet, ainsi que l’identifiant de la carte bancaire
      # - Lemon Way répond
      # @param attrs [Hash{String, Symbol => String, Number}]
      #   - :wallet* [String] Identifiant du wallet, max 256
      #   - :card_id* [String] Identifiant de la carte bancaire à désactiver max 12
      # @return [string] identifiant de la carte enregistrée
      def unregister_card attrs
        camelize_and_ensure_keys! attrs, %i(wallet cardId)
        query :post, :UnregisterCard, attrs do |response|
          response["card"]["id"]
        end
      end

      def money_in_with_card_id attrs, &block
        camelize_and_ensure_keys! attrs, %i(wallet cardId amountTot), %i(amountCom message)
        query :post, :MoneyInWithCardId, attrs, &block
      end

      # Avec la méthode « SendPayment », le MARCHAND peut envoyer un paiement à un CLIENT existant ou non, ou à un autre MARCHAND existant :
      # * L’application de vente envoie à Lemon Way le numéro de mobile du CLIENT ou le code PDV du MARCHAND qu’il souhaite payer, le montant à payer, et un commentaire
      # * Lemon Way répond
      #
      # @param attrs [Hash{String, Symbol => String, Number}]
      #   - :debit_wallet* [string] Identifiant du wallet à débiter, [0 : 256] car, ex: 33612345678 ou taxi67
      #   - :credit_wallet* Identifiant du wallet à créditer, [0 : 256] car, ex: 33612345678 ou taxi67
      #   - :amount* Montant du paiement, 2 décimales, ex : 15.00
      #   - :message Commentaire du paiement, [0 :140] car, ex: Commande numéro 245
      # @return [HashWithIndifferentAccess{key => String, Number}]
      #  - :id [String] identifiant de la demande, max 255
      #  - :date [String] Date de la demande, french 10/09/2011 18:09:27
      #  - :sen [String] Wallet débiteur
      #  - :rec [String] Wallet bénéficiaire
      #  - :deb [Number] Montant à débiter, ex: 15.00
      #  - :cred [Number] Montant à créditer ex: 15.00
      #  - :com [Number] Commission de la demande, ex: 0.00
      #  - :msg [String] Commentaire de la demande, ex: Commande numéro 245
      #  - :status [String] Non utilisé dans le kit MARCHAND
      def send_payment attrs
        camelize_and_ensure_keys! attrs, %i(debitWallet creditWallet amount), %i(message)
        query :post, :SendPayment, attrs do |response|
          response["trans"]["hpay"]
        end
      end

      def register_iban attrs, &block
        camelize_and_ensure_keys! attrs, %i(wallet holder bic iban dom1 dom2)
        query :post, :RegisterIBAN, attrs, &block
      end

      def money_out attrs, &block
        camelize_and_ensure_keys! attrs, %i(wallet amountTot), %i(amountCom message desc)
        query :post, :MoneyOut, attrs, &block
      end

      def get_payment_details attrs, &block
        camelize_and_ensure_keys! attrs, %i(transactionId transactionComment)
        query :post, :GetPaymentDetails, attrs, &block
      end

      def get_money_in_details attrs, &block
        camelize_and_ensure_keys! attrs, %i(), %i(transactionId transactionComment)
        query :post, :GetMoneyInDetails, attrs, &block
      end

      def get_money_out_details attrs, &block
        camelize_and_ensure_keys! attrs, %i(), %i(transactionId transactionComment)
        query :post, :GetMoneyOutDetails, attrs, &block
      end

    end
    module WebMerchant
      include Base
      extend self
      include HTTParty

      format :xml

    end
  end
end
