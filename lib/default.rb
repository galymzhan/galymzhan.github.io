# All files in the 'lib' directory will be loaded
# before nanoc starts compiling.

require 'pathname'

require 'rouge'
require 'redcarpet'
require 'rouge/plugins/redcarpet'
require 'compass'

Encoding.default_internal = 'UTF-8'

include Nanoc::Helpers::Blogging
include Nanoc::Helpers::LinkTo
include Nanoc::Helpers::HTMLEscape

class ::SexyHTML < ::Redcarpet::Render::HTML
  include ::Rouge::Plugins::Redcarpet
  include ::Redcarpet::Render::SmartyPants
end

module Nanoc::Helpers::Blogging
  def published_articles
    sorted_articles.select { |item| item.attributes.fetch(:published, true) }
  end
end
