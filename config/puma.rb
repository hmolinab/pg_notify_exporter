require 'puma/daemon'

# How many worker processes to run.
workers 0

# Bind the server to
bind 'tcp://0.0.0.0:9292'

# Load “path” as a rackup file.
# The default is “config.ru”.
rackup DefaultRackup

# Store the pid of the server in the file at “path”.
pidfile 'var/puma.pid'

# Use “path” as the file to store the server info state. This is
# used by “pumactl” to query and control the server.
state_path 'var/puma.state'

daemonize

# Disable request logging.
# The default is “false”.
log_requests
quiet 

stdout_redirect 'log/stdout.log'

lowlevel_error_handler do |e, env, status|
  if status == 400
    message = "The server could not process the request due to an error, such as an incorrectly typed URL, malformed syntax, or a URL that contains illegal characters.\n"
  else
    message = "An error has occurred, and engineers have been informed. Please reload the page. If you continue to have problems, contact support@example.com\n"
    Rollbar.critical(e)
  end

  [status, {}, [message]]
end


# see more:
# https://stackoverflow.com/questions/19946153/how-do-i-use-pumas-configuration-file
