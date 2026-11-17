import unittest,numpy as np
from metrics import *
class MetricTests(unittest.TestCase):
    def test_waiting_service_not_net(self):
        x=paired_workload([5],[1],[1],[5],1)
        self.assertEqual(x,dict(QSA=4.,SSA=0.,WLA=4.,WLA_net=0.))
    def test_interaction_sign(self):
        self.assertEqual(float(interaction(10,8,7,4)),1.)
    def test_zero_loss_no_fake_gain(self):
        self.assertTrue(np.isnan(relative_benefit(0,0)))
    def test_priority_equal(self):self.assertEqual(priority_gap([1,2],[2,4]),0.)
    def test_bootstrap_paired_constant(self):
        m,l,u=paired_bootstrap(np.full((10,2),[1,-2]));np.testing.assert_array_equal(m,[1,-2]);np.testing.assert_array_equal(l,m);np.testing.assert_array_equal(u,m)
if __name__=='__main__':unittest.main()
