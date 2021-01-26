# How to enable text search for Chinese, Japanese and Korean

Pleroma's full text search feature is powered by PostgreSQL's native [text search](https://www.postgresql.org/docs/current/textsearch.html), it works well out of box for most of languages, but needs extra configurations for some asian languages like Chinese, Japanese and Korean (CJK).


## Setup and test the new search config

In most cases, you would need an extension installed to support parsing CJK text. Here are a few extension you may choose from, or you are more than welcome to share additional ones you found working for you with the rest of Pleroma community.

 * [a generic n-gram parser](https://github.com/huangjimmy/pg_cjk_parser) supports Simplifed/Traditional Chinese, Japanese, and Korean
 * [a Korean parser](https://github.com/i0seph/textsearch_ko) based on mecab
 * [a Japanese parser](https://www.amris.co.jp/tsja/index.html) based on mecab
 * [zhparser](https://github.com/amutu/zhparser/) is a PostgreSQL extension base on the Simple Chinese Word Segmentation(SCWS)
 * [another Chinese parser](https://github.com/jaiminpan/pg_jieba) based on Jieba Chinese Word Segmentation
 
Once you have the new search config , make sure you test it with the `pleroma` user in PostgreSQL (change `YOUR.CONFIG` to your real configuration name)
```
SELECT ts_debug('YOUR.CONFIG', '安装和配置Nginx, ElixirとErlangをインストールします');
```
Check output of the query, and see if it matches your expectation.


## Update default search config for Pleroma database
```
ALTER DATABASE pleroma SET default_text_search_config = 'YOUR.CONFIG';
```


## Update index 

### if you are using GIN
In index definition, `YOUR.CONFIG` has to be hardcoded due to [PostgreSQL requirement](https://www.postgresql.org/docs/current/textsearch-tables.html#TEXTSEARCH-TABLES-INDEX), so you have to update it from the original value of `english`:
```
DROP INDEX objects_fts;
CREATE INDEX objects_fts ON objects USING gin(to_tsvector('YOUR.CONFIG', data->>'content'));
```

### if you are using RUM
update trigger function definition to use the default search config of Pleroma database
```
CREATE OR REPLACE FUNCTION objects_fts_update() RETURNS trigger AS $$
    begin
    new.fts_content := to_tsvector(new.data->>'content');
    return new;
    end
$$ LANGUAGE plpgsql
```
and, if not on a fresh Pleroma install, refresh index for existing statuses:
```
UPDATE objects SET updated_at = NOW();
```

## Restart database connection
Since some changes above will only apply with a new database connection, you will have to restart either Pleroma or PostgreSQL process, or use `pg_terminate_backend` SQL command without restarting either. 

Now the search results of statuses should be much more friendly for your language of choice, the results for searching users and tags were not changed, as the default parsing/matching should work for most cases. 
