class RateLimitedTestQueueAL
  def self.perform(succeed)
    raise(AngellistApi::Error::TooManyRequests, 'error') unless succeed
  end
end

describe Resque::Plugins::RateLimited::AngellistQueue do
  before do
    # expect(Resque::Plugins::RateLimited::AngellistQueue).to receive(:paused?).at_least(:once) # .and_return(false)
  end

  describe 'enqueue' do
    it 'enqueues to the correct queue with the correct parameters' do
      expect(Resque).to receive(:enqueue_to).with(
        :angellist_api,
        Resque::Plugins::RateLimited::AngellistQueue,
        RateLimitedTestQueueAL.to_s,
        true
      )

      Resque::Plugins::RateLimited::AngellistQueue.enqueue(RateLimitedTestQueueAL, true)
    end
  end

  describe 'perform' do
    before { Resque.inline = true }
    after  { Resque.inline = false }

    context 'with everything' do
      it 'calls the class with the right parameters' do
        expect(RateLimitedTestQueueAL).to receive(:perform).with('test_param')
        Resque::Plugins::RateLimited::AngellistQueue.enqueue(RateLimitedTestQueueAL, 'test_param')
      end
    end

    context 'with rate limit exception' do
      it 'pauses queue when request fails' do
        expect(Resque::Plugins::RateLimited::AngellistQueue).to receive(:rate_limited_requeue)
        expect(Resque::Plugins::RateLimited::AngellistQueue).to receive(:pause_until)
        Resque::Plugins::RateLimited::AngellistQueue.enqueue(RateLimitedTestQueueAL, false)
      end
    end
  end
end
