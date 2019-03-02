# My Blog

It's a Hugo static site that is apparently pretty speedy. I'll be using this repository to write some notes, make some reflections and other stuff.

## Syncing to an S3 bucket

I'm not doing netlify because that's too easy.

`aws s3 sync --acl public-read --sse --delete ./public/ s3://roryhow-blog`

# TODO

[ ] IaaC all of the things (i.e do some terraform)
[ ] Set up some CI to the s3 bucket rather than having to sync manually
[ ] Write some posts (preferably about ML and thesis)
