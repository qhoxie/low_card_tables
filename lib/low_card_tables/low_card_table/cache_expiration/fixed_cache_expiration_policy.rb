module LowCardTables
  module LowCardTable
    module CacheExpiration
      class FixedCacheExpirationPolicy
        def initialize(expiration_time)
          unless expiration_time && expiration_time.kind_of?(Numeric) && expiration_time >= 0.0
            raise "Expiration time must be a nonnegative number, not: #{expiration_time.inspect}"
          end

          @expiration_time = expiration_time
        end

        def stale?(cache_time, current_time)
          (current_time - cache_time) > @expiration_time
        end
      end
    end
  end
end