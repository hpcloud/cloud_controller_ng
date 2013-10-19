class Logyard
  def self.report_event(event, message, user, app)
    name = app[:name]
    event = {
      :user => user,
      :app => app,
      :event => event,
      :instance_index => -1,
      :message => message,
    }
    Steno.logger("cc.logyard").info("TIMELINE #{event.to_json}")
  end
end