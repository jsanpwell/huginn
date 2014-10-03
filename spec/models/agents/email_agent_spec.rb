require 'spec_helper'

describe Agents::EmailAgent do
  it_behaves_like EmailConcern

  def get_message_part(mail, content_type)
    mail.body.parts.find { |p| p.content_type.match content_type }.body.raw_source
  end

  before do
    @checker = Agents::EmailAgent.new(:name => "something", :options => { :expected_receive_period_in_days => "2", :subject => "something interesting" })
    @checker.user = users(:bob)
    @checker.save!
  end

  after do
    ActionMailer::Base.deliveries = []
  end

  describe "#receive" do
    it "immediately sends any payloads it receives" do
      expect(ActionMailer::Base.deliveries).to eq([])

      event1 = Event.new
      event1.agent = agents(:bob_rain_notifier_agent)
      event1.payload = { :data => "Something you should know about" }
      event1.save!

      event2 = Event.new
      event2.agent = agents(:bob_weather_agent)
      event2.payload = { :data => "Something else you should know about" }
      event2.save!

      Agents::EmailAgent.async_receive(@checker.id, [event1.id])
      Agents::EmailAgent.async_receive(@checker.id, [event2.id])

      expect(ActionMailer::Base.deliveries.count).to eq(2)
      expect(ActionMailer::Base.deliveries.last.to).to eq(["bob@example.com"])
      expect(ActionMailer::Base.deliveries.last.subject).to eq("something interesting")
      expect(get_message_part(ActionMailer::Base.deliveries.last, /plain/).strip).to eq("Event\n  data: Something else you should know about")
      expect(get_message_part(ActionMailer::Base.deliveries.first, /plain/).strip).to eq("Event\n  data: Something you should know about")
    end

    it "can receive complex events and send them on" do
      stub_request(:any, /wunderground/).to_return(:body => File.read(Rails.root.join("spec/data_fixtures/weather.json")), :status => 200)
      stub.any_instance_of(Agents::WeatherAgent).is_tomorrow?(anything) { true }
      @checker.sources << agents(:bob_weather_agent)

      Agent.async_check(agents(:bob_weather_agent).id)

      Agent.receive!

      plain_email_text = get_message_part(ActionMailer::Base.deliveries.last, /plain/).strip
      html_email_text = get_message_part(ActionMailer::Base.deliveries.last, /html/).strip

      expect(plain_email_text).to match(/avehumidity/)
      expect(html_email_text).to match(/avehumidity/)
    end
  end
end
