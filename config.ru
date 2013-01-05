use Rack::Static, :urls => [''], :root => 'output', :index => 'index.html'
run lambda { |env| [200, {}, ''] }
