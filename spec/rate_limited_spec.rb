require 'spec_helper'
require 'resque/rate_limited'

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
  it 'should be compliance with Resque::Plugin document' do
    expect { Resque::Plugin.lint(Resque::Plugins::RateLimited) }.to_not raise_error
  end

  shared_examples_for 'queue' do |queue_suffix|
    it 'should queue to the correct queue' do
      queue_param = queue_suffix.empty? ? RateLimitedTestQueue.queue_private : "#{RateLimitedTestQueue.queue_name_private}#{queue_suffix}"
      expect(Resque).to receive(:enqueue_to).with(queue_param, nil, nil)
      RateLimitedTestQueue.rate_limited_enqueue(nil, nil)
    end
  end

  context 'when queue is not paused' do
    before do
      allow(RateLimitedTestQueue).to receive(:paused?).and_return(false)
    end

    describe 'enqueue' do
      include_examples 'queue', ''
    end

    describe 'paused?' do
      it { expect(RateLimitedTestQueue.paused?).to be false }
    end

    describe 'perform' do
      it 'should requeue the job on failure' do
        expect(Resque).to receive(:enqueue_to)
        RateLimitedTestQueue.perform(false)
      end

      it 'should not requeue the job on success' do
        expect(Resque).not_to receive(:enqueue_to)
        RateLimitedTestQueue.perform(true)
      end
    end

    describe 'pause' do
      it 'should rename the queue to paused' do
        expect(Resque.redis).to receive(:renamenx).with("queue:#{RateLimitedTestQueue.queue_name_private}", "queue:#{RateLimitedTestQueue.queue_name_private}_paused")
        RateLimitedTestQueue.pause
      end
    end

    describe 'un_pause' do
      it 'should not unpause the queue' do
        expect(Resque.redis).not_to receive(:renamenx).with("queue:#{RateLimitedTestQueue.queue_name_private}", "queue:#{RateLimitedTestQueue.queue_name_private}_paused")
        RateLimitedTestQueue.un_pause
      end
    end

    describe 'pause_until' do
      before do
        allow(Resque.redis).to receive(:renamenx).and_return(true)
      end

      it 'should pause the queue' do
        expect(RateLimitedTestQueue).to receive(:pause)
        RateLimitedTestQueue.pause_until(Time.now + (5 * 60 * 60))
      end

      it 'should schedule an unpause job' do
        expect(Resque::Plugins::RateLimited::UnPause).to receive(:enqueue)
                                                  .with(nil, 'RateLimitedTestQueue')
        RateLimitedTestQueue.pause_until(nil)
      end
    end
  end

  context 'when queue is paused' do
    before do
      allow(RateLimitedTestQueue).to receive(:paused?).and_return(true)
    end

    describe 'enqueue' do
      include_examples 'queue', '_paused'
    end

    describe 'paused?' do
      it { expect(RateLimitedTestQueue.paused?).to be true }
    end

    describe 'perform' do
      it 'should not execute the block' do
        expect(Resque).to receive(:enqueue_to).with("#{RateLimitedTestQueue.queue_name_private}_paused", RateLimitedTestQueue, true)
        expect(RateLimitedTestQueue).not_to receive(:perform)
        RateLimitedTestQueue.around_perform_with_check_and_requeue(true)
      end
    end

    describe 'un_pause' do
      it 'should rename the queue to live' do
        expect(Resque.redis).to receive(:renamenx).with("queue:#{RateLimitedTestQueue.queue_name_private}_paused", "queue:#{RateLimitedTestQueue.queue_name_private}")
        RateLimitedTestQueue.un_pause
      end
    end
  end

  describe 'when queue is paused and Resque is in inline mode' do
    let(:resque_prefix) { Resque::Plugins::RateLimited::RESQUE_PREFIX }
    let(:queue) { resque_prefix + RateLimitedTestQueue.queue_name_private }
    let(:paused_queue) { resque_prefix + RateLimitedTestQueue.paused_queue_name }

    before do
      allow(Resque.redis).to receive(:exists).with(queue).and_return(false)
      allow(Resque.redis).to receive(:exists).with(paused_queue).and_return(true)
      Resque.inline = true
    end

    after do
      Resque.inline = false
    end

    it 'would be paused' do
      expect(Resque.redis.exists(queue)).to eq false
      expect(Resque.redis.exists(paused_queue)).to eq true
    end

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
    before do
      allow(RateLimitedTestQueue).to receive(:paused?).and_return(true)
    end
    context 'with not found error' do
      before do
        allow(Resque.redis).to receive(:renamenx).and_raise(Redis::CommandError.new('ERR no such key'))
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
        allow(Resque.redis).to receive(:renamenx).and_raise(Redis::CommandError.new('ERR something else'))
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
      before do
        allow(Resque.redis).to receive(:exists).with("queue:#{RateLimitedTestQueue.queue_name_private}_paused").and_return(true)
        allow(Resque.redis).to receive(:exists).with("queue:#{RateLimitedTestQueue.queue_name_private}").and_return(false)
      end

      it 'should return the true if the paused queue exists' do
        expect(RateLimitedTestQueue.paused?).to eq(true)
      end
    end

    context 'with un paused queue' do
      before do
        allow(Resque.redis).to receive(:exists).with("queue:#{RateLimitedTestQueue.queue_name_private}_paused").and_return(false)
        allow(Resque.redis).to receive(:exists).with("queue:#{RateLimitedTestQueue.queue_name_private}").and_return(true)
      end

      it 'should return the false if the main queue exists exist' do
        expect(RateLimitedTestQueue.paused?).to eq(false)
      end
    end

    context 'with unknown queue state' do
      before do
        allow(Resque.redis).to receive(:exists).with("queue:#{RateLimitedTestQueue.queue_name_private}_paused").and_return(false)
        allow(Resque.redis).to receive(:exists).with("queue:#{RateLimitedTestQueue.queue_name_private}").and_return(false)
      end

      it 'should return the default' do
        expect(RateLimitedTestQueue.paused?(true)).to eq(true)
        expect(RateLimitedTestQueue.paused?(false)).to eq(false)
      end
    end
  end
end
