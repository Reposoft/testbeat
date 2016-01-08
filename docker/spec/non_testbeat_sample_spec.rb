
require 'net/http'

describe "Some spec'd service" do

  it "Responds 200 or 301 at root, for health checks" do
    res = Net::HTTP.get_response('specd', '/', 80)
    expect(res.code).to eq "200"
    expect(res.body).to match /html.*body.*It works/
  end

end
