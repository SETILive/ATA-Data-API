desc 'Bundle application and upload it to S3'
task :bundle_app do
  require 'aws-sdk'
  AWS.config access_key_id: '***REMOVED***', secret_access_key: '***REMOVED***'
  
  # hang onto the working branch
  working_branch = `git rev-parse --abbrev-ref HEAD`.chomp
  
  # switch to the deploy branch
  `git checkout -b bundled_deploy`
  
  # precompile assets
  # `rm -rf public/assets`
  # `rake assets:precompile`
  
  # package the gems
  `bundle package`
  
  # commit the changes
  # `git add -f public/assets`
  `git add -f vendor/cache`
  `git commit -a -m "deploying"`
  
  # export the app
  `git archive -o frank.tar HEAD`
  `gzip frank.tar`
  
  # S3 setup
  s3 = AWS::S3.new
  bucket = s3.buckets['***REMOVED***']
  old_bundle = bucket.objects['frank.tar.gz']
  
  # move the old bundle if it exists
  if old_bundle.exists?
    timestamp = old_bundle.last_modified.strftime('%H%M-%d%m%y')
    old_bundle.move_to "frank-#{ timestamp }.tar.gz"
  end
  
  # upload the new bundle
  print 'Uploading...'
  new_bundle = bucket.objects['frank.tar.gz']
  new_bundle.write file: 'frank.tar.gz'
  puts '...done'
  `rm -f frank.tar.gz`
  
  # checkout the working branch
  `git checkout #{ working_branch }`
  `git branch -D bundled_deploy`
end
