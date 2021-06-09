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

# Disable request logging.
# The default is “false”.
quiet

# see more:
# https://stackoverflow.com/questions/19946153/how-do-i-use-pumas-configuration-file
