#!/usr/bin/env ruby

require 'mail'

class UploadErrorChecker
  def check!
    uploads = Upload.where("status like 'error%' and status not like 'error: RuntimeError - duplicate%' and created_at >= ?", 1.hour.ago)
    if uploads.size > 5
      mail = Mail.new do
        from "webmaster@danbooru.donmai.us"
        to "hennign@oregonstate.edu"
        subject "[danbooru] Upload error count at #{uploads.size}"
        body uploads.map {|x| x.status}.join("\n")
      end
      mail.delivery_method :sendmail
      mail.deliver
    end
  end
end

