# frozen_string_literal: true

name 'cinc-omnibus'

run_list 'test::default'

cookbook 'cinc-omnibus', path: '.'
cookbook 'chef-ingredient', git: 'https://github.com/chef-cookbooks/chef-ingredient.git', branch: 'main'
cookbook 'test', path: './test/cookbooks/test'

Dir.children('./test/cookbooks/test/recipes').grep(/\.rb\z/).sort.each do |recipe|
  recipe_name = File.basename(recipe, '.rb')

  named_run_list recipe_name.to_sym, 'test::' + recipe_name
end
