#!/usr/bin/ruby

require 'optparse'
require 'json'
require 'pp'
require_relative './cookbook_decompiler.rb'
# dependencies for the lib running node tests, preferrably discovered here instead of in node loop
require 'rspec'
require 'set'
require 'open3'

def get_hostname(node: $node, vagrant_dir: $vagrant_dir)
  [node, vagrant_dir]
  cmd_hostname = "cat /etc/hostname"
  hostname = Open3.popen3("cd #{ vagrant_dir + node }; vagrant ssh -c \"#{cmd_hostname}\"") { |stdin, stdout, stderr, wait_thr| stdout.read }
  puts "Vagrant node hostname: #{hostname}"
  return hostname
end

# Get first matching subgroup
#  stripped of quotes and leading/trailing whitespace
def get_match(pattern, text)
  matches = pattern.match(text)
  the_match = matches[1]
  the_match.delete("\"").strip()
end

# Prepared commands from run_tests are fed in here.
def run_integration_tests_bats(tests)
  puts "Running bats tests for cookbooks."

  tests.sort().each do |cmd|
    #print "Running bats test #{cmd}"
    system("cd #{ $vagrant_dir + $node }; vagrant ssh -c \"#{cmd}\"")
  end
end

def run_integration_tests(recipes)
  # Now its time for the bats tests.
  integration_tests =  []
  repos_backup_testing = false
  # Next we reduce recipes to cookbooks
  if recipes.include?("repos-backup")
    recipes.delete("repos-backup")
    repos_backup_testing = true
  end

  integration_result_format = "--format RspecJunitFormatter"
  node_path_to_cookbooks = ""
  sync_data = File.read($vagrant_dir + $node + "/.vagrant/machines/default/virtualbox/synced_folders")
  sync_info = JSON.parse(sync_data)
  sync_info['virtualbox'].each do |key,value|
    if /cookbooks/.match(value['hostpath'])
      node_path_to_cookbooks = value['guestpath'].split("/")[0..-2].join("/")
      break
    end
  end
  recipes.each do |recipe|
    # break off sub-recipe name from cookbook name
    #  repos-channel::haproxy -> repos-channel
    puts "Recipe: #{recipe}"
    cookbook_name = recipe.split("::")[0]
    path_to_cookbook_integration_tests = "cookbooks/#{cookbook_name}/test/integration/default"
    if Dir.exists?(path_to_cookbook_integration_tests)
      puts "Found: #{path_to_cookbook_integration_tests}"
      Dir.glob("#{path_to_cookbook_integration_tests}/*.rb").each do |path_to_file|
        # /tmp/vagrant-chef-?/chef-solo-1/
        # cd #{$vagrant_dir}#{node}; vagrant ssh -c
        puts "node_path_to_cookbooks: #{node_path_to_cookbooks}. path_to_file: #{path_to_file}"
        integration_tests.push("rspec #{integration_result_format} #{node_path_to_cookbooks}/#{path_to_file} > /vagrant/generated_integration_results_#{cookbook_name}.xml")
      end
    else
      puts "Couldn't find #{path_to_cookbook_integration_tests}"
    end
  end
  path_to_node_integration_tests = "#{$vagrant_dir}#{$node}/integration/default"
  if Dir.exists?(path_to_node_integration_tests)
    Dir.glob("#{path_to_node_integration_tests}/*.rb").each do |path_to_file|
      just_filename = path_to_file.split("/")[-1]
      integration_tests.push("rspec #{integration_result_format} /vagrant/integration/default/#{just_filename} > /vagrant/generated_integration_results_#{$node}.xml")
    end
  else
    puts "No node-specific integration tests available for #{$node} in #{path_to_node_integration_tests}"
  end

  if integration_tests.empty?()
    puts "No integration tests for node #{$node}"
  else
    run_integration_tests_bats(integration_tests)
  end
  if repos_backup_testing
    system("cd #{ $vagrant_dir + $node }; vagrant ssh -c \"sudo chef-solo -j /tmp/vagrant-chef/dna.json -c /tmp/vagrant-chef/solo.rb -o 'recipe[cms-base],recipe[repos-backup]'\"")
  end

  #backup_test_cmd = "rspec -f j /tmp/vagrant-chef-?/chef-solo-1/cookbooks/repos-backup/test/integration/default/repos-backup_spec.rb > integration_repos-backup.txt"
  #run_integration_tests_bats([backup_test_cmd])
end

def run_rspec(node, path, outf, verbose)
  puts "Starting test: #{path}"
  rspec_cmd = "NODE=#{node} rspec #{path} --format documentation --out #{outf}.txt --format html --out #{outf}.html --format RspecJunitFormatter --out #{outf}.xml --format progress"
  IO.popen(rspec_cmd, :err=>[:child, :out], :external_encoding=>"UTF-8") do |io|
    io.each_char do |c|
      if verbose then
        $stdout.print c
        if c == '.' or c == 'F' or c == "\n" then $stdout.flush end
      end
    end
  end
  return $?.success?
end

def run_tests(recipes, hostname, out: "#{$vagrant_dir}#{$node}/generated/", testglob: "test/acceptance/*.rb", verbose: true)
  [recipes, hostname, out, testglob, verbose]
  rspec_ok = true # if no tests => no failure

  if Dir.exists?(out)
    puts "Using existing output directory #{out}"
    Dir.glob("#{out}acceptance*").each do |previous|
      File.delete(previous);
    end
  else
    puts "Creating output directory #{out}"
  end

  run_history = Set.new()
  recipes.each do |recipe|
    # break off sub-recipe name from cookbook name
    #  repos-channel::haproxy -> repos-channel
    #puts "Recipe: " + recipe
    cookbook_name = recipe.split("::")[0]
    cookbook_specs = Dir.glob("cookbooks/#{cookbook_name}/#{testglob}")
    if cookbook_specs.length == 0
      puts "No generic acceptance tests available for #{recipe} in #{$chef_dir}cookbooks/#{cookbook_name}/test/acceptance"
    end
    cookbook_specs.each do |path_to_file|
      if not run_history.include?(path_to_file)
        run_history.add(path_to_file)
        just_filename = path_to_file.split("/")[-1]
        rspec_ok = run_rspec(hostname, path_to_file, "#{out}acceptance_#{cookbook_name}_#{just_filename}", verbose) && rspec_ok
      end
    end
  end

  path_to_node_acceptance_tests = "#{$vagrant_dir}#{$node}/acceptance"
  if Dir.exists?(path_to_node_acceptance_tests)
    rspec_ok = run_rspec(hostname, "#{path_to_node_acceptance_tests}/*.rb", "#{out}acceptance_node", verbose) && rspec_ok
  else
    puts "No node-specific acceptance tests available for #{$node} in #{path_to_node_acceptance_tests}"
  end

  # Print a summary in the end
  concat = File.open("#{out}acceptance.txt", "w")
  Dir.glob("#{out}acceptance_*.txt").each do |generated_docs|
    puts generated_docs
    concat.write("#" + generated_docs)
    File.readlines(generated_docs).each do |line|
      concat.write(line)
      results = /^\d+ examples, (\d+) failure.?/.match(line)
      if results
        puts line
      end
    end
  end
  concat.close unless concat.nil?

  return rspec_ok
end

# guestint: run on-guest integration tests
def main(node: "labs01", provider: "virtualbox", retest: false, guestint: true, verbose: true)
  [node, provider, retest, guestint, verbose]
  $node = node
  options = {}

  $chef_dir = ""
  $vagrant_dir = $chef_dir + "nodes/"
  $bats_test_tmp = $vagrant_dir + "bats_tmp/"

  $vagrant_file = $vagrant_dir + $node + "/Vagrantfile"
  #$vagrant_chef_dir = %x[ cd #{$vagrant_dir}#{node}; vagrant ssh -c "find /tmp/vagrant-chef/ -maxdepth 2 -type d -name cookbooks ]
  #"/tmp/vagrant-chef/chef-solo-1/"

  puts "### node: #{$node} (#{$vagrant_dir + $node}) ###"
  recipes = []


  if not (Dir.exists?($vagrant_dir + $node) and File.exists?($vagrant_file))
    $stderr.puts "No such Vagrant node #{ $node }"
    exit 1
  end

  # ----------------------------------------------------------------------------------
  # Start Vagrant or run provision on an already running node

  cwd_to_node = "cd #{ $vagrant_dir + $node}; "

  v_status = %x[ cd #{ $vagrant_dir + $node}; vagrant status ]
  runlist_file = "/tmp/#{$node}_testbeat.runlist";
  if /poweroff/.match(v_status) or /not created/.match(v_status)
    puts "Vagrant node not running, start and provision..."
    if File.exists?(runlist_file)
      File.delete(runlist_file)
    end
    vagrant_cmd = cwd_to_node + "vagrant up --provider=#{provider}"
  elsif /running/.match(v_status)
    # Add "if runlist file older than 1 h, assume force_long"
    hostname = get_hostname()
    if retest and File.exists?(runlist_file)
      old_run = File.read(runlist_file)
      #run_match = /Run List expands to \[(.*?)\]/.match(old_run)
      recipes = old_run.split(", ")
      print "Recipes (rerun based on #{runlist_file}): "
      puts recipes
      all_cookbooks = CookbookDecompiler.resolve_dependencies(recipes).to_a
      puts "All cookbooks included: " + all_cookbooks.join(", ")
      # code duplicated from uncached runlist below
      rspec_ok = true
      if guestint
        rspec_ok = rspec_ok && run_integration_tests(all_cookbooks)
      end
      rspec_ok = rspec_ok && run_tests(all_cookbooks, hostname)
      if not rspec_ok
        puts "There were test failures!"
        exit 1
      end
      puts "All tests for cached runlist passed"
      exit 0
    else
      puts "Vagrant node running, provision..."
      vagrant_cmd = cwd_to_node + "vagrant provision"
    end
  else
    $stderr.puts "Unknown Vagrant state: #{v_status}"
  end

  # ----------------------------------------------------------------------------------
  # Build an array consisting of custom tests to be compared with Vagrant provision
  # output

  # First we look up tests for our custom Vagrant output checker
  test_collection = []

  if options[:tests]
    tests = options[:tests].split(",")
    tests.each do |opt|
        test_file_path = opt
        if File.exists?(test_file_path)
        contents = File.read(test_file_path)
        obj = JSON.parse(contents)
        obj["tests"].each do |test|
          test_collection.push(test)
        end
      end
    end
  end

  #vagrant_run_output = %x[ export LANG=en_US.UTF-8; #{vagrant_cmd} ]
  vagrant_run_output = ''
  IO.popen(vagrant_cmd, :err=>[:child, :out], :external_encoding=>"UTF-8") do |io|
    io.each do |line|
      if verbose then puts line end
      vagrant_run_output << line + "\n"
    end
  end
  result = $?.success?

  if not result
    $stderr.puts "Vagrant run failed! See output below"
    $stderr.puts vagrant_run_output
    exit 1
  else
    puts "Vagrant provision completed."
    hostname = get_hostname()

    # Run List expands to [repos-channel::haproxy, cms-base::folderstructure, repos-apache2, repos-subversion, repos-rweb, repos-trac, repos-liveserver, repos-indexing, repos-snapshot, repos-vagrant-labs]
    run_match = /Run List expands to \[(.*?)\]/.match(vagrant_run_output)
    if run_match
      dump_file = File.new("/tmp/#{$node}_testbeat.runlist","w+",0755)
      dump_file.write(run_match[1]) # should be run_match[1] but role-leanserver edit above...
      dump_file.close()

      recipes = run_match[1].split(", ")
      puts "Run list extracted from Vagrant: " + recipes.join(", ")
      all_cookbooks = CookbookDecompiler.resolve_dependencies(recipes).to_a
      puts "All cookbooks included: " + all_cookbooks.join(", ")
      puts "test_collection (presumably not used anymore): " + test_collection.join(", ");
      # the run code has been duplicated for cached runlist above
      rspec_ok = true
      if guestint
        rspec_ok = rspec_ok && run_integration_tests(all_cookbooks)
      end
      rspec_ok = rspec_ok && run_tests(all_cookbooks, hostname)
      if not rspec_ok
        exit 1
      end
    else
      puts "Unable to find text 'Run List expands to' in Vagrant output :("
    end
  end

end
