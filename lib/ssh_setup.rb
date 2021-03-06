#!/usr/bin/env ruby
require 'fileutils'
require 'pathname'
require 'tmpdir'

build_dir    = ARGV[0]
cache_dir    = ARGV[1]
env_dir      = ARGV[2]
ssh_dir      = File.expand_path "#{ENV['HOME']}/.ssh"

def alert(str)
  str.split('\n').each do |line|
    puts "       !!!! #{line}"
  end
end

def arrow(str)
  str.split("\n").each do |line|
    puts ":::::> #{line}"
  end
end

arrow "############################################"
arrow "         GIT DELPOY KEY BUILDPACK           "
arrow "############################################"
arrow "             DELPOYING IS BEST              "
arrow "############################################"


arrow "ssh dir is #{ssh_dir}"
################# Get the key from heroku's environment config #################
key_file_path = File.join env_dir, 'GITHUB_DEPLOY_KEY'
ssh_key = File.open(key_file_path, &:read) if File.exist? key_file_path

if ssh_key.nil?
  alert "GITHUB_DEDLOY_KEY not set"
  alert "  Try `heroku config:add GITHUB_DEPLOY_KEY=<your private token>`"
  exit 1
end


############# Get the known host from heroku's environment config ##############
host_hash_path = File.join env_dir, 'GITHUB_HOST_HASH'
host_hash = File.open(host_hash_path, &:read) if File.exist? host_hash_path

if host_hash.nil?
  alert "GITHUB_HOST_HASH not set"
  alert "  Try `heroku config:add GITHUB_HOST_HASH=<hash>`"
  exit 1
end

###################### Process and clean up the ssh keys #######################
fingerprint = nil
temp_key = nil
clean_host_hash = nil

Dir.mktmpdir 'ssh_buidpack' do |dir|
  # Process key to standardise it's format
  `ssh-keygen -e -P '' -f #{key_file_path} < /dev/null > #{dir}/ssh_buildpack_key.pub.rfc 2>/dev/null`
  `ssh-keygen -i -P '' -f #{dir}/ssh_buildpack_key.pub.rfc > #{dir}/ssh_buildpack_key.pub 2>/dev/null`

  # # Process host hash to standardise it's format
  # `ssh-keygen -e -P '' -f #{key_file_path} < /dev/null > #{dir}/host_hash.pub.rfc 2>/dev/null`
  # `ssh-keygen -i -P '' -f #{dir}/host_hash.pub.rfc > #{dir}/host_hash.pub 2>/dev/null`

  fingerprint = `ssh-keygen -l -f #{dir}/ssh_buildpack_key.pub | awk '{print $2}'`

  # only used to be sure the passed key was valid
  temp_key = `echo "#{fingerprint}" | tr -ds ':' '' | egrep -ie "[a-f0-9]{32}" 2>/dev/null`

  # clean_host_hash = `cat "#{dir}/host_hash.pub"`

  if temp_key.strip == ''
    alert "GITHUB_DEPLOY_KEY was invalid"
    exit 1
  else
    arrow "Using GITHUB_DEPLOY_KEY #{fingerprint}"
  end

end


# Create the ssh directory on the server
Dir.mkdir(ssh_dir, 0700) unless File.exists?(ssh_dir)

# Create id_rsa file and write contents
File.open "#{ssh_dir}/id_rsa", 'w' do |f|
  f.write ssh_key
end
FileUtils.chmod 0600, "#{ssh_dir}/id_rsa"
arrow "Wrote ssh key to user's ssh dir"

#create known_hosts file and write contents
File.open "#{ssh_dir}/known_hosts", 'w' do |f|
  f.write host_hash
end
FileUtils.chmod 0600, "#{ssh_dir}/known_hosts"
arrow "Wrote host hash to user's known hosts"

File.open "#{ssh_dir}/config", 'w' do |f|
  f.puts "IdentityFile #{ssh_dir}/id_rsa"
  f.puts "host github.com"
  f.puts "     user git"
  f.puts "     IdentityFile #{ssh_dir}/id_rsa"
end
FileUtils.chmod 0600, "#{ssh_dir}/config"
arrow "Wrote config to user's config"

test_connection = `ssh -T git@github.com 2>&1`
unless test_connection.include? "successfully authenticated"
  alert "ssh key error"
  alert test_connection
  exit 1
end
