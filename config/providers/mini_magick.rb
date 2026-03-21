# frozen_string_literal: true

Hanami.app.register_provider :mini_magick, namespace: true do
  prepare { require "mini_magick" }

  start do
    MiniMagick.configure { |config| config.logger = slice[:logger] }

    register :core, MiniMagick
    register :image, MiniMagick::Image
  end
end
