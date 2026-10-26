# Example site

```sh
cd example
bundle install
bundle exec jekyll serve
```

Open http://127.0.0.1:4000 and search. The first build downloads the model
from the Hugging Face Hub; later builds reuse cached embeddings.
