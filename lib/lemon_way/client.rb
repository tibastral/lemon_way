require "active_support/core_ext/hash"
require 'active_support/builder'
require "httparty"


module LemonWay
  module Client
    module Base

      attr_accessor :default_attributes, :required_default_attributes, :optional_default_attributes

      class Error < Exception ; end

      def init(opts={})
        opts.symbolize_keys!.camelize_keys!.ensure_keys %i(baseUri), required_default_attributes + optional_default_attributes
        self.base_uri opts.delete(:baseUri)
        self.default_attributes =  opts
      end

      def make_body(method_name, attrs={})
        options = {}
        options[:builder] = Builder::XmlMarkup.new(:indent => 2)
        options[:builder].instruct!
        options[:builder].__send__(:method_missing, method_name, xmlns: "Service") do
          attrs.each do |key, value|
            ActiveSupport::XmlMini.to_tag(key, value, options)
          end
        end
      end

      def query(type, method, attrs={})
        response_body = send(type, "/", :body => make_body(method, attrs)) || {}
        response_body = response_body.with_indifferent_access.underscore_keys(true)
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
        attrs.camelize_keys!.ensure_keys required_attributes + required_default_attributes, optional_attributes + optional_default_attributes
      end

      module_eval do
        def define_query_method name, required_attrs=[], optional_attrs=[], &block
          define_method name do |attrs|
            camelize_and_ensure_keys! attrs.update(default_attributes), required_attrs, optional_attrs
            query :post, name.to_s.camelize, attrs, &block
          end
        end
      end
    end

    #Il est possible de créer un Wallet en marque blanche avec notre plateforme de paiement.
    #L’usage étant le cadeau commun, la liste, la cagnotte, etc.
    #La plateforme offre la possibilité de créer un compte de paiement pour les utilisateurs « récolteurs » qui effectuent une liste.
    #
    #Le paiement s’effectue ensuite à partir d’utilisateurs « normaux » qui utilisent leur carte pour payer le teneur de la liste (listier).
    #Le teneur de la liste peut ensuite faire un virement vers sa banque lorsque sa « récolte » est terminée.
    #
    #La plateforme gère les comptes des listiers, les virements, les paiements par carte faits sur le compte du listier.
    #Le listier peut également approvisionner son propre compte avec sa carte bancaire.
    #
    #En marque blanche, Lemon Way ne fait pas de communication directe avec les clients finaux
    #(listiers ou payeurs).
    #Il est également possible de créer des comptes de type « marchand » pour les marchands favoris que vos utilisateurs payent en général, pour simplifier le paiement, avec un interfaçage spécial à prévoir chez les eMarchands (accords bi-latéraux à trouver).
    #
    #Dans la suite de ce document, l’acquéreur de la solution en marque blanche sera désigné par « MARQUE BLANCHE ».
    #
    #Lemon Way met à disposition de la MARQUE BLANCHE :
    # - Un backoffice général permettant de visualiser les opérations du système et les clients
    # - Un backoffice Pro, permettant de visualiser les paiements versés à la MARQUE BLANCHE ou prélevés par LEMON WAY sur le compte de la MARQUE BLANCHE (commissions ou autre)
    # - Des webservices dans un DIRECTKIT
    # - Des pages web dans un WEBKIT
    #
    #==Prérequis
    #LEMON WAY fournit à la MARQUE BLANCHE diverses informations permettant de les identifier :
    #- Un login et le mot de passe associé, permettant à la MARQUE BLANCHE de se connecter au backoffice et au DIRECTKIT
    #- Un code PDV marchand, correspondant au compte marchand sur lequel la MARQUE BLANCHE recevra ses éventuelles commissions, et sur lequel LEMON WAY prélèvera ses commissions
    #- Un identifiant permettant d’utiliser le WEBKIT (le mot de passe associé est à générer sur le backoffice, par la MARQUE BLANCHE)

    module WhiteLabel
      include Base
      extend self
      include HTTParty

      self.required_default_attributes = %i(wlLogin wlPass wlPDV version language channel walletIp)
      self.optional_default_attributes = %i(format model walletUa)

      format :xml

      #Avec la méthode « RegisterWallet », le système MARQUE BLANCHE demande à Lemon Way la création d’un wallet.
      #* L’utilisateur saisit ses données
      #* L’application appelle le webservice de Lemon Way
      #* Lemon Way enregistre les données et crée le compte de paiement
      #* L’application traite la réponse de Lemon Way et affiche un message de confirmation
      #@param attrs [Hash{String, Symbol => String, Number}]
      #@return [String] Identifiant du wallet inscrit avec succès, ex: ￼￼336123456 78
      define_query_method :register_wallet, %i(wallet clientMail clientTitle clientFirstName clientLastName), %i(clientTitle clientHandset) do |response|
        response[:wallet][:id]
      end

      #Avec la méthode « GetWalletDetails», la MARQUE BLANCHE peut vérifier les détails d’un wallet de son système : statut, solde, IBAN rattaché, etc.
      #@param wallet [String] Wallet ID
      #@return [HashWithIndifferentAccess{key => String, Number}]
      #  - id    [String] Identifiant du wallet, ex: 33612345678 ou taxi67
      #  - bal   [Number] Solde du wallet ex: 23.90
      #  - name  [String] Nom et prénom, ex: Jean Dupont
      #  - email [String] Email ex: Jean.dupont@email.c om
      #  - iban [Hash] Correspond à l’IBAN lié au wallet
      #    - s [Integer] Correspond au statut de l’IBAN
      #      - 0 : pas d’iban lié au wallet
      #      - 2 : en attente de vérification
      #      - 5 : vérifié, approuvé, utilisable
      #      - 9 : rejeté
      #  - s [Integer] Statut du wallet :
      #    - 5 : enregistré (statut donné après création) 6 : documents envoyés
      #    - 12 : fermé
      define_query_method :get_wallet_details, %i(wallet) do |response|
        response[:wallet]
      end

      #Crédit de wallet avec carte bancaire, sans 3D-Secure.
      #Cette méthode ne nécessite qu’un seul point d’intégration
      #
      #Avec la méthode « MoneyIn », le système effectue un rechargement du wallet par carte
      #bancaire, sans 3D-Secure :
      #* L’application MARQUE BLANCHE envoie à Lemon Way l’identifiant du wallet à créditer, l’identifiant de la carte bancaire associée au wallet, le montant à créditer, et un commentaire
      #* Lemon Way répond
      #
      #@param attrs [Hash{String, Symbol => String, Number}]
      #  - :wallet* [String] Identifiant du wallet à créditer length [0 : 256] car, ex: 33612345678 ou taxi67
      #  - :card_type* [integer] Type de carte bancaire, [1] car, can be 0 (CB), 1 (Visa) or 2 (Mastercard)
      #  - :card_number* [Number] Numéro à 16 chiffres, [16] car, ex: ￼4972000011112222
      #  - :card_crypto* [Number] Cryptogramme de la carte à 3 chiffres, [3] car, ex: 123
      #  - :card_date* [String] Date d’expiration de la carte, MM/yyyy, ex: ￼12/2013
      #  - :amount_tot* [Number] Montant à débiter de la CB, 2 décimales, ex: 15.00
      #  - :amount_com [Number] Montant que la MARQUE BLANCHE souhaite prélever, 2 décimales, ex: 1.00
      #  - :message [String] Commentaire du paiement, [0 :140] car, , ex: ￼Commande numéro 245
      #
      #@return [HashWithIndifferentAccess{key => String, Number}]
      #  - :id      [String] Identifiant de la transaction, max length 255_
      #  - :mlabel  [String] Numéro de carte masqué, ex : XXXX XXXX XXXX 9845_
      #  - :date    [String] Date de la demande, ex : 10/09/2011 18:09:27
      #  - :sen     [String] Vide dans ce cas
      #  - :rec     [String] Wallet à créditer, ex: Pizza56
      #  - :deb     [Number] 0.00 dans ce cas, ex: 0.00
      #  - :cred    [Number] Montant à créditer au wallet (total moins la commission) , ex: 15.00
      #  - :com     [Number] Commission prélevée par la MARQUE BLANCHE , ex:2.00
      #  - :msg     [Number] Commentaire ex : Commande numéro 245
      #  - :status  Non utilisé dans le kit MARQUE BLANCHE
      define_query_method :money_in, %i(wallet cardType cardNumber cardCrypto cardDate amountTot), %i(amountCom message) do |response|
        block ? block.call(response["trans"]["hpay"]) : response["trans"]["hpay"]
      end

      #Initialisation crédit de wallet par CB 3D-Secure
      #
      #Cette fonctionnalité nécessitera 3 points d’intégration par la MARQUE BLANCHE
      #* Un appel au DIRECTKIT pour initialiser les données du rechargement de wallet Une redirection du site web de la MARQUE BLANCHE vers le WEBKIT
      #* Une page de retour sur laquelle le WEBKIT POST le résultat
      #
      #Cinématique
      #1. L’application MARQUE BLANCHE envoie à Lemon Way l’identifiant du wallet, un token de requête qui lui permettra de traiter la réponse du WEBKIT, et les montants
      #2. Lemon Way retourne un token de money-in
      #3. Le site web de la MARQUE BLANCHE redirige le CLIENT vers le WEBKIT de Lemon Way, en passant le token de money-in en paramètre GET. (Voir paragraphe 8.3.3 MoneyInWebFinalize \: finalisation de rechargement)
      #
      #@param attrs [Hash{String, Symbol => String, Number}]
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
      #@return [String] Token de paiement à passer en GET vers l’URL du webkit
      define_query_method :money_in_web_init, %i(wallet amountTot wkToken returnUrl errorUrl cancelUrl), %i(amountCom message useRegisteredCard) do |response|
        response["moneyinweb"]["token"]
      end


      #Enregistrement de carte bancaire
      #
      #Avec la méthode  RegisterCard, le système peut envoyer une demande d’association d’une carte bancaire à un wallet :
      #- L’application MARQUE BLANCHE envoie à Lemon Way l’identifiant du wallet, ainsi que les informations sur la carte bancaire
      #- Lemon Way répond
      #@param attrs [Hash{String, Symbol => String, Number}]
      #   - :wallet* [String] Identifiant du wallet, max 256
      #   - :card_type* [String] Type de la carte. Can be 0 (CB), 1 (Visa) or 2 (Mastercard)
      #   - :card_number* [Number] Numéro de la carte, 16 chiffres
      #   - :card_code* Cryptogramme[String] de la carte, [3 : 4] car
      #   - :card_date* [String] Date d’expiration de la carte, 7 car
      #@return [String] Identifiant de la carte enregistrée
      define_query_method :register_card, %i(wallet cardType cardNumber cardCode cardDate) do |response|
        response["card"]["id"]
      end


      #Effacement de carte bancaire
      #
      #Pour le moment, une seule carte est autorisée par wallet.
      #Avec la méthode « UnregisterCard », le système peut envoyer une demande de désactivation
      #de la carte bancaire liée à un wallet :
      #- L’application MARQUE BLANCHE envoie à Lemon Way l’identifiant du wallet, ainsi que l’identifiant de la carte bancaire
      #- Lemon Way répond
      #@param attrs [Hash{String, Symbol => String, Number}]
      #   - :wallet* [String] Identifiant du wallet, max 256
      #   - :card_id* [String] Identifiant de la carte bancaire à désactiver max 12
      #@return [string] identifiant de la carte enregistrée
      define_query_method :unregister_card, %i(wallet cardId) do |response|
        response["card"]["id"]
      end

      #Crédit de wallet avec carte bancaire pré-enregistrée
      #
      #Avec la méthode MoneyInWithCardId, le système peut envoyer une demande de rechargement du wallet :
      #1. L’application MARQUE BLANCHE envoie à Lemon Way l’identifiant du wallet à créditer, l’identifiant de la carte bancaire associée au wallet, le montant à créditer, et un commentaire
      #2. Lemon Way répond
      #
      #@param attrs [Hash{String, Symbol => String, Number}]
      # - :wallet*     [String] Identifiant du wallet à crébiter, [0 : 256] car
      # - :cardId*     [String] Identifiant de la carte bancaire associée au wallet, [0 : 256] car
      # - :amountTot*  [Number] Montant à débiter de la CB
      # - :amountCom   [Number] Montant que la MARQUE BLANCHE souhaite prélever
      # - :message     [String] Commentaire du paiement
      #@return [HashWithIndifferentAccess{key => String, Number}]
      define_query_method :money_in_with_card_id, %i(wallet cardId amountTot), %i(amountCom message) do |response|
        response[:trans][:hpay]
      end

      # Paiement entre wallets
      #
      #Avec la méthode « SendPayment », le MARCHAND peut envoyer un paiement à un CLIENT existant ou non, ou à un autre MARCHAND existant :
      #* L’application de vente envoie à Lemon Way le numéro de mobile du CLIENT ou le code PDV du MARCHAND qu’il souhaite payer, le montant à payer, et un commentaire
      #* Lemon Way répond
      #
      #@param attrs [Hash{String, Symbol => String, Number}]
      #   - :debit_wallet* [string] Identifiant du wallet à débiter, [0 : 256] car, ex: 33612345678 ou taxi67
      #   - :credit_wallet* Identifiant du wallet à créditer, [0 : 256] car, ex: 33612345678 ou taxi67
      #   - :amount* Montant du paiement, 2 décimales, ex : 15.00
      #   - :message Commentaire du paiement, [0 :140] car, ex: Commande numéro 245
      #@return [HashWithIndifferentAccess{key => String, Number}]
      #  - :id [String] identifiant de la demande, max 255
      #  - :date [String] Date de la demande, french 10/09/2011 18:09:27
      #  - :sen [String] Wallet débiteur
      #  - :rec [String] Wallet bénéficiaire
      #  - :deb [Number] Montant à débiter, ex: 15.00
      #  - :cred [Number] Montant à créditer ex: 15.00
      #  - :com [Number] Commission de la demande, ex: 0.00
      #  - :msg [String] Commentaire de la demande, ex: Commande numéro 245
      #  - :status [String] Non utilisé dans le kit MARCHAND
      define_query_method :send_payment, %i(debitWallet creditWallet amount), %i(message) do |response|
        response["trans"]["hpay"]
      end

      #Pré-enregistrement d’IBAN
      define_query_method :register_iban, %i(wallet holder bic iban dom1 dom2) do |response|
        response[:iban][:s]
      end

      #Virement
      define_query_method :money_out, %i(wallet amountTot), %i(amountCom message desc) do |response|
        response[:trans][:hpay]
      end

      # Rechercher un paiement
      # @return [Array (HashWithIndifferentAccess{key => String, Number})]
      define_query_method :get_payment_details, %i(transactionId transactionComment) do |response|
        response[:trans][:hpay]
      end

      # Rechercher un money-in
      # @return [Array (HashWithIndifferentAccess{key => String, Number})]
      define_query_method :get_money_in_details, %i(), %i(transactionId transactionComment) do |response|
        response[:trans][:hpay]
      end

      #  Rechercher un money-out
      # @return [Array (HashWithIndifferentAccess{key => String, Number})]
      define_query_method :get_money_out_details, %i(), %i(transactionId transactionComment) do |response|
        response[:trans][:hpay]
      end

    end
    module WebMerchant
      include Base
      extend self
      include HTTParty

      self.optional_default_attributes = %i()
      self.required_default_attributes = %i()

      format :xml

    end
  end
end
