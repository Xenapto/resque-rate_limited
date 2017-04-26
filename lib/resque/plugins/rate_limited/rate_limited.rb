module Resque
  module Plugins
    module RateLimited
      RESQUE_PREFIX = 'queue:'.freeze
      MUTEX = 'Resque::Plugins::RateLimited'.freeze

      def around_perform_with_check_and_requeue(*params)
        paused = false
        with_lock do
          paused = paused?
          Resque.enqueue_to(paused_queue_name, self, *params) if paused
        end
        return if paused
        yield
      end

      def rate_limited_enqueue(klass, *params)
        with_lock do
          if paused?
            Resque.enqueue_to(paused_queue_name, klass, *params)
          else
            Resque.enqueue_to(@queue, klass, *params)
          end
        end
      end

      def rate_limited_requeue(klass, *params)
        # if the queue is empty, this was the last job - so queue to the paused queue
        with_lock do
          if paused?(true)
            Resque.enqueue_to(paused_queue_name, klass, *params)
          else
            Resque.enqueue_to(@queue, klass, *params)
          end
        end
      end

      def pause_until(timestamp)
        UnPause.enqueue(timestamp, name) if pause
      end

      def un_pause
        Resque.redis.renamenx(prefixed(paused_queue_name), prefixed(@queue))
        true
      rescue Redis::CommandError => e
        raise unless e.message == 'ERR no such key'
        false
      end

      def pause
        Resque.redis.renamenx(prefixed(@queue), prefixed(paused_queue_name))
        true
      rescue Redis::CommandError => e
        raise unless e.message == 'ERR no such key'
        false
      end

      def paused?(unknown = false)
        # parameter is what to return if the queue is empty, and so the state is unknown
        if Resque.inline
          false
        elsif Resque.redis.exists(prefixed(@queue))
          false
        elsif Resque.redis.exists(prefixed(paused_queue_name))
          true
        else
          unknown
        end
      end

      def paused_queue_name
        "#{@queue}_paused".to_sym
      end

      def prefixed(name)
        "#{RESQUE_PREFIX}#{name}"
      end

      def with_lock
        if Resque.inline
          yield
        else
          RedisMutex.with_lock(MUTEX, block: 60, expire: 120) { yield }
        end
      end

      def find_class(klass)
        return klass if klass.is_a? Class
        return Object.const_get(klass) unless klass.include?('::')
        klass.split('::').reduce(Object) do |mod, class_name|
          mod.const_get(class_name)
        end
      end
    end
  end
end
