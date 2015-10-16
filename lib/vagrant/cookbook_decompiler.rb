
#!/usr/bin/ruby

require 'set'

$cookbooks_dir = config_path = File.join(Dir.pwd, "cookbooks")

def get_default_recipe(cookbook_name)
  return File.open($cookbooks_dir + "/" + cookbook_name + "/recipes/default.rb","r")
end

def get_include_lines(file)
  lines_with_include = []
  file.each_line do |line|
    if /include_recipe/.match(line)
      lines_with_include.push(line)
    end
  end
  return lines_with_include
end

def get_cookbook_name(line)
  name_match = /include_recipe.?"([^"]*)"/.match(line)
  if name_match
    just_name = name_match[1].split("::")[0]
    return just_name
  else
    raise "Line #{line} does not contain an include_recipe statement"
  end
end

def remove_recipe_part(name)
  return name.split("::")[0]
end

def get_included_cookbooks(cookbook_name)
  just_name = remove_recipe_part(cookbook_name)
  recipe_default = get_default_recipe(just_name)
  lines = get_include_lines(recipe_default)
  names = []
  lines.each do |line|
    name = get_cookbook_name(line)
    names.push(name) unless names.include? name
  end
  return names
end

module CookbookDecompiler

  def CookbookDecompiler.resolve_dependencies(cookbook_names)


    # First level cookbooks are obviously included, so let's make them the starting set.
    cookbooks_to_be_returned = Set.new(cookbook_names)

    loop do
      # Next, find the second level cookbooks.
      second_set = Set.new()
      cookbooks_to_be_returned.each do |name|
        included_cookbooks = get_included_cookbooks(name)
        second_set = second_set.merge(included_cookbooks)
      end
      if second_set.subset? cookbooks_to_be_returned
        return cookbooks_to_be_returned
      else
        cookbooks_to_be_returned.merge(second_set)
      end
    end
    # If all second level cookbooks are already in the set, we're done.
    # otherwise we repeat, treating the second level cookbooks as first level.

  end
end
