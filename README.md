# NetworkX.rb

[![Gem Version](https://badge.fury.io/rb/networkx.svg)](https://badge.fury.io/rb/networkx)

[NetworkX](https://networkx.github.io/) is a very popular Python library, that handles various use-cases of the Graph Data Structure.  
This project intends to provide a working alternative to the Ruby community, by closely mimicing as many features as possible. 

## List of contents

- [Installing](#installing)
- [Usage](#Usage)
- [Document](#document)
- [Contributing](#contributing)
- [License](#license)

## Installing

- install it yourself as:
```console
$ gem install networkx
```


- Or use Bundler & Gemfile
  1. add this line to your application's Gemfile:
  ```ruby
  gem 'networkx'
  ```
  2. And then execute:
  ```console
  $ bundle install
  ```

## Usage

```ruby
require 'networkx'

g = NetworkX::Graph.new
g.add_edge('start', 'stop')
``` 

Small-scale Vietoris-Rips persistence is available for undirected graphs with at most
32 nodes through `NetworkX.vietoris_rips_persistence`. It is truncated at dimension two
and returns F2 persistence intervals for H0 and H1, including the creator and killer
simplex of each finite interval.

## Document

You can read [Document](https://SciRuby.github.io/networkx.rb/) for this library.

## Contributing

Your contributions are always welcome!  
Please have a look at the [contribution guidelines](.github/CONTRIBUTING.md) first. :tada:

## License

The MIT License 2017 - [Athitya Kumar](https://github.com/athityakumar).   
Please have a look at the [LICENSE.md](LICENSE.md) for more details.
