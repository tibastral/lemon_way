__Caution : Still under developpement and subject to changes__ 
# LemonWay

Ruby API client to query LemonWay web merchant and blank label APIs

Documentation at http://rubydoc.info/github/Paymium/lemon_way

## Installation

Add this line to your application's Gemfile:

    gem 'lemon_way'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install lemon_way

## Usage

```ruby
LemonWay::Client::BlankLabel.init   wl_login: "test",
                                    wl_pass: "test",
                                    wl_pdv: "test",
                                    language: "fr",
                                    version: "1.0"

LemonWay::Client::BlankLabel.register_wallet my_hash
```


## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
