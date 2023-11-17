from fastembed.embedding import FlagEmbedding as Embedding
embedding_model = Embedding(model_name="BAAI/bge-small-en-v1.5", max_length=512) 

def get_embedding(text):
    text = text.decode('utf-8')
    [embedding] = list(embedding_model.embed(text))
    return embedding.tolist()
