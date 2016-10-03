require 'spec_helper'
require 'resque/rate_limited'

class RateLimitedTestQueueAL
  def self.perform(succeed)
    raise(AngellistApi::Error::TooManyRequests, 'error') unless succeed
  end
end

describe Resque::Plugins::RateLimited::AngellistQueue do
  before do
    Resque::Plugins::RateLimited::AngellistQueue.stub(:paused?).and_return(false)
  end

  describe 'enqueue' do
    it 'enqueues to the correct queue with the correct parameters' do
      Resque.should_receive(:enqueue_to).with(
        :angellist_api,
        Resque::Plugins::RateLimited::AngellistQueue,
        RateLimitedTestQueueAL.to_s,
        true
      )
      Resque::Plugins::RateLimited::AngellistQueue
        .enqueue(RateLimitedTestQueueAL, true)
    end
  end

  describe 'perform' do
    before do
      Resque.inline = true
    end
    context 'with everything' do
      it 'calls the class with the right parameters' do
        RateLimitedTestQueueAL.should_receive(:perform).with('test_param')
        Resque::Plugins::RateLimited::AngellistQueue
          .enqueue(RateLimitedTestQueueAL, 'test_param')
      end
    end

    context 'with rate limit exception' do
      before do
        Resque::Plugins::RateLimited::AngellistQueue.stub(:rate_limited_requeue)
      end
      it 'pauses queue when request fails' do
        Resque::Plugins::RateLimited::AngellistQueue.should_receive(:pause_until)
        Resque::Plugins::RateLimited::AngellistQueue
          .enqueue(RateLimitedTestQueueAL, false)
      end
    end
  end
end
