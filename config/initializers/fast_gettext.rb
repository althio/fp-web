require 'gettext_i18n_rails/string_interpolate_fix'

FastGettext.add_text_domain 'app', :path => 'locale', :type => :po
FastGettext.default_available_locales = %w(da de en es fr id it ja nl pl pt tl)
FastGettext.default_text_domain = 'app'
