class RateLimitedTestQueue
end

describe Resque::Plugins::RateLimited::UnPause do
  describe 'perform' do
    it 'unpauses the queue' do
      expect(RateLimitedTestQueue).to receive(:un_pause)
      Resque::Plugins::RateLimited::UnPause.perform(RateLimitedTestQueue)
    end
  end

  describe 'enqueue' do
    context 'with no queue defined' do
      it 'does not queue the job' do
        expect(Resque).to receive(:respond_to?).exactly(3).times.and_return(true)
        expect(Resque).not_to receive(:enqueue_at_with_queue)
        Resque::Plugins::RateLimited::UnPause.enqueue(Time.now, RateLimitedTestQueue)
      end
    end

    context 'with queue defined' do
      it 'queues the job' do
        Resque::Plugins::RateLimited::UnPause.queue = :queue_name

        expect(Resque).to receive(:enqueue_at_with_queue).with(
          :queue_name,
          nil,
          Resque::Plugins::RateLimited::UnPause,
          RateLimitedTestQueue
        )

        Resque::Plugins::RateLimited::UnPause.enqueue(nil, RateLimitedTestQueue)
      end
    end
  end

  describe 'class_from_string' do
    it 'converts unqualified classes' do
      expect(Resque::Plugins::RateLimited::UnPause.class_from_string(RateLimitedTestQueue.to_s))
        .to eq(RateLimitedTestQueue)
    end

    it 'converts qualified classes' do
      expect(Resque::Plugins::RateLimited::UnPause.class_from_string(Resque::Plugins::RateLimited::UnPause.to_s))
        .to eq(Resque::Plugins::RateLimited::UnPause)
    end
  end
end
