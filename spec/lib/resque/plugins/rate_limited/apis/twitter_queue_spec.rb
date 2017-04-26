class RateLimitedTestQueueTw
  def self.perform(succeed)
    raise(Twitter::Error::TooManyRequests.new('', 'x-rate-limit-reset' => (Time.now + 60).to_i)) unless succeed
  end
end

describe Resque::Plugins::RateLimited::TwitterQueue do
  before do
    expect(Resque::Plugins::RateLimited::TwitterQueue).to receive(:paused?).at_least(:once).and_return(false)
  end

  describe 'enqueue' do
    it 'enqueues to the correct queue with the correct parameters' do
      expect(Resque).to receive(:enqueue_to).with(
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
    before { Resque.inline = true }
    after  { Resque.inline = false }

    context 'with everything' do
      it 'calls the class with the right parameters' do
        expect(RateLimitedTestQueueTw).to receive(:perform).with('test_param')
        Resque::Plugins::RateLimited::TwitterQueue
          .enqueue(RateLimitedTestQueueTw, 'test_param')
      end
    end

    context 'with rate limit exception' do
      it 'pauses queue when request fails' do
        expect(Resque::Plugins::RateLimited::TwitterQueue).to receive(:rate_limited_requeue)
        expect(Resque::Plugins::RateLimited::TwitterQueue).to receive(:pause_until)
        Resque::Plugins::RateLimited::TwitterQueue.enqueue(RateLimitedTestQueueTw, false)
      end
    end
  end
end
