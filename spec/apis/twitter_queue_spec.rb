require 'spec_helper'
require 'resque/rate_limited'

class RateLimitedTestQueueTw
  def self.perform(succeed)
    raise(Twitter::Error::TooManyRequests
      .new('', 'x-rate-limit-reset' => (Time.now + 60).to_i)) unless succeed
  end
end

describe Resque::Plugins::RateLimited::TwitterQueue do
  before do
    Resque::Plugins::RateLimited::TwitterQueue.stub(:paused?).and_return(false)
  end

  describe 'enqueue' do
    it 'enqueues to the correct queue with the correct parameters' do
      Resque.should_receive(:enqueue_to).with(
        :twitter_api,
        Resque::Plugins::RateLimited::TwitterQueue,
        RateLimitedTestQueueTw.to_s,
        true
      )
      Resque::Plugins::RateLimited::TwitterQueue
        .enqueue(RateLimitedTestQueueTw, true)
    end
  end

  describe 'perform' do
    before do
      Resque.inline = true
    end
    context 'with everything' do
      it 'calls the class with the right parameters' do
        RateLimitedTestQueueTw.should_receive(:perform).with('test_param')
        Resque::Plugins::RateLimited::TwitterQueue
          .enqueue(RateLimitedTestQueueTw, 'test_param')
      end
    end

    context 'with rate limit exception' do
      before do
        Resque::Plugins::RateLimited::TwitterQueue.stub(:rate_limited_requeue)
      end
      it 'pauses queue when request fails' do
        Resque::Plugins::RateLimited::TwitterQueue.should_receive(:pause_until)
        Resque::Plugins::RateLimited::TwitterQueue
          .enqueue(RateLimitedTestQueueTw, false)
      end
    end
  end
end
