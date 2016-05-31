import os
os.environ['CUDA_VISIBLE_DEVICES'] = ''

import tensorflow as tf
import numpy as np
from train_resnet import model

def creat_predictor(dirname):
    sess = tf.Session()
    in_training = tf.Variable(True, name='in_training', trainable=False)
    in_data = tf.placeholder(tf.uint8, (1, 19, 19, 48), name='input')
    with tf.device('/cpu:0'):
        keep_prob = tf.Variable(1.0, name='keep_prob', trainable=False)

        predictions = model(in_data, in_training, keep_prob,
                            num_modules=16,
                            depth=192)

    checkpoint = tf.train.latest_checkpoint(dirname)
    assert checkpoint
    saver = tf.train.Saver()
    saver.restore(sess, checkpoint)

    def predict(features):
        # faetures maps to last index
        features = np.transpose(features, [1, 2, 0])
        feed = {in_data: features[np.newaxis, ...], in_training: False}
        return sess.run(predictions, feed_dict=feed)

    return predict


class Predictor(object):
    def __init__(self, dirname):
        self.predictor = creat_predictor(dirname)

    def predict(self, features):
        return self.predictor(features)
