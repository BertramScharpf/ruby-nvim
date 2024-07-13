#
#  neovim/meta.rb  --  Metadata: Version info etc.
#

module Neovim

  class Meta

    def initialize name, **params
      @name, @params = name, params
    end

    attr_reader :name

    %i(
      commit
      version
      license
      summary
      description
      homepage
      authors
      email
      metadata
    ).each { |p|
      define_method p do @params[ p] end
    }

    alias website homepage


    def version_h
      @params[ :version] =~ /\Av?(\d+)(?:\.(\d+)(?:\.(\d+)))(?:-(.*))?\z/
      {
        major:      $1,
        minor:      $2,
        patch:      $3,
        prerelease: $4,
        commit:     @params[ :commit],
      }
    end

    def version_a
      version_h.values_at :major, :minor, :patch, :prerelease
    end

    def attributes
      {
        website: @params[ :homepage],
        license: @params[ :license ],
      }
    end


    def mk_gemspec spec
      spec.name          = @name
      spec.version       = @params[:version ]
      spec.authors       = @params[:authors ]
      spec.email         = @params[:email   ]
      spec.summary       = @params[:summary ]
      spec.homepage      = @params[:homepage]
      spec.license       = @params[:license ]
    end

  end

end

