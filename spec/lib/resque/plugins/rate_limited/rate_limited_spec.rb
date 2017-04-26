class RateLimitedTestQueue
  extend Resque::Plugins::RateLimited

  @queue = :test

  def self.perform(succeed)
    rate_limited_requeue(self, succeed) unless succeed
  end

  def self.queue_name_private
    @queue.to_s
  end

  def self.queue_private
    @queue
  end
end

describe Resque::Plugins::RateLimited do
  it 'complies with Resque::Plugin documentation' do
    expect { Resque::Plugin.lint(Resque::Plugins::RateLimited) }.to_not raise_error
  end

  shared_examples_for 'queue' do |queue_suffix|
    it 'should queue to the correct queue' do
      queue_param = if queue_suffix.empty?
                      RateLimitedTestQueue.queue_private
                    else
                      "#{RateLimitedTestQueue.queue_name_private}#{queue_suffix}".to_sym
                    end

      expect(Resque).to receive(:enqueue_to).with(queue_param, nil, nil)
      RateLimitedTestQueue.rate_limited_enqueue(nil, nil)
    end
  end

  describe 'perform' do
    it 'should not requeue the job on success' do
      expect(Resque).not_to receive(:enqueue_to)
      RateLimitedTestQueue.perform(true)
    end
  end

  context 'when queue is not paused' do
    before do
      expect(RateLimitedTestQueue).to receive(:paused?).and_return(false)
    end

    describe 'enqueue' do
      include_examples 'queue', ''
    end

    describe 'paused?' do
      it { expect(RateLimitedTestQueue.paused?).to be false }
    end

    describe 'perform' do
      it 'should requeue the job on failure' do
        expect(Resque).to receive(:enqueue_to).with(:test, RateLimitedTestQueue, false)
        RateLimitedTestQueue.perform(false)
      end
    end
  end

  context 'when queue is paused' do
    before do
      expect(RateLimitedTestQueue).to receive(:paused?).and_return(true)
    end

    describe 'enqueue' do
      include_examples 'queue', '_paused'
    end

    describe 'paused?' do
      it { expect(RateLimitedTestQueue.paused?).to be true }
    end

    describe 'perform' do
      it 'should requeue the job on failure' do
        expect(Resque).to receive(:enqueue_to).with(:test_paused, RateLimitedTestQueue, false)
        RateLimitedTestQueue.perform(false)
      end

      it 'should not execute the block' do
        expect(Resque).to receive(:enqueue_to).with(
          "#{RateLimitedTestQueue.queue_name_private}_paused".to_sym,
          RateLimitedTestQueue,
          true
        )

        expect(RateLimitedTestQueue).not_to receive(:perform)
        RateLimitedTestQueue.around_perform_with_check_and_requeue(true)
      end
    end
  end

  context 'pause and unpause' do
    describe 'pause' do
      it 'should rename the queue to paused' do
        expect(Resque.redis).to receive(:renamenx).with(
          "queue:#{RateLimitedTestQueue.queue_name_private}",
          "queue:#{RateLimitedTestQueue.queue_name_private}_paused"
        )
        RateLimitedTestQueue.pause
      end
    end

    describe 'un_pause' do
      it 'should rename the queue to live' do
        expect(Resque.redis).to receive(:renamenx).with(
          "queue:#{RateLimitedTestQueue.queue_name_private}_paused",
          "queue:#{RateLimitedTestQueue.queue_name_private}"
        )

        RateLimitedTestQueue.un_pause
      end
    end

    describe 'pause_until' do
      it 'should pause the queue' do
        expect(RateLimitedTestQueue).to receive(:pause)
        RateLimitedTestQueue.pause_until(Time.now + (5 * 60 * 60))
      end

      it 'should schedule an unpause job' do
        expect(RateLimitedTestQueue).to receive(:pause).and_return(true)
        expect(Resque::Plugins::RateLimited::UnPause).to receive(:enqueue).with(nil, 'RateLimitedTestQueue')
        RateLimitedTestQueue.pause_until(nil)
      end
    end
  end

  describe 'when queue is paused and Resque is in inline mode' do
    let(:queue) { RateLimitedTestQueue.prefixed(RateLimitedTestQueue.queue_name_private) }
    let(:paused_queue) { RateLimitedTestQueue.prefixed(RateLimitedTestQueue.paused_queue_name) }

    before { Resque.inline = true }
    after  { Resque.inline = false }

    it 'says it is not paused' do
      expect(RateLimitedTestQueue.paused?).to eq false
    end

    it 'performs the job' do
      expect do
        # Stack overflow unless handled
        RateLimitedTestQueue.rate_limited_enqueue(RateLimitedTestQueue, true)
      end.not_to raise_error
    end
  end

  describe 'find_class' do
    it 'works with symbol' do
      expect(RateLimitedTestQueue.find_class(RateLimitedTestQueue)).to eq RateLimitedTestQueue
    end

    it 'works with simple string' do
      expect(RateLimitedTestQueue.find_class('RateLimitedTestQueue')).to eq RateLimitedTestQueue
    end

    it 'works with complex string' do
      expect(RateLimitedTestQueue.find_class('Resque::Plugins::RateLimited')).to eq Resque::Plugins::RateLimited
    end
  end

  context 'with redis errors' do
    context 'with not found error' do
      before do
        expect(Resque.redis).to receive(:renamenx).and_raise(Redis::CommandError.new('ERR no such key'))
      end

      describe 'pause' do
        it 'should not throw exception' do
          expect { RateLimitedTestQueue.pause }.to_not raise_error
        end
      end

      describe 'un_pause' do
        it 'should not throw exception' do
          expect { RateLimitedTestQueue.un_pause }.to_not raise_error
        end
      end
    end

    context 'with other errror' do
      before do
        expect(Resque.redis).to receive(:renamenx).and_raise(Redis::CommandError.new('ERR something else'))
      end

      describe 'pause' do
        it 'should throw exception' do
          expect { RateLimitedTestQueue.pause }.to raise_error(Redis::CommandError)
        end
      end

      describe 'un_pause' do
        it 'should throw exception' do
          expect { RateLimitedTestQueue.un_pause }.to raise_error(Redis::CommandError)
        end
      end
    end
  end

  describe 'paused?' do
    context 'with paused queue' do
      it 'should return true if the paused queue exists' do
        expect(Resque.redis).to receive(:exists)
          .with("queue:#{RateLimitedTestQueue.queue_name_private}_paused")
          .and_return(true)

        expect(Resque.redis).to receive(:exists)
          .with("queue:#{RateLimitedTestQueue.queue_name_private}")
          .and_return(false)

        expect(RateLimitedTestQueue.paused?).to eq(true)
      end
    end

    context 'with un paused queue' do
      it 'should return false if the main queue exists' do
        expect(Resque.redis).to receive(:exists)
          .with("queue:#{RateLimitedTestQueue.queue_name_private}")
          .and_return(true)

        expect(RateLimitedTestQueue.paused?).to eq(false)
      end
    end

    context 'with unknown queue state' do
      it 'should return the default' do
        expect(Resque.redis).to receive(:exists)
          .with("queue:#{RateLimitedTestQueue.queue_name_private}_paused")
          .twice
          .and_return(false)

        expect(Resque.redis).to receive(:exists)
          .with("queue:#{RateLimitedTestQueue.queue_name_private}")
          .twice
          .and_return(false)

        expect(RateLimitedTestQueue.paused?(true)).to eq(true)
        expect(RateLimitedTestQueue.paused?(false)).to eq(false)
      end
    end
  end
end
