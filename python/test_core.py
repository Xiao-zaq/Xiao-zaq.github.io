"""Independent analytic and invariant tests; no V173 runs are invoked."""
import math
import unittest
import numpy as np
from p4core import *

class PhysicsTests(unittest.TestCase):
    def test_equal_availability(self):
        for scale in [.25,.5,1,2,4]:
            lam,mu=reliability_rates(.97,60,scale)
            self.assertAlmostEqual(mu/(lam+mu),.97)
            self.assertAlmostEqual(1/mu,60/scale)
    def test_hazard_partition(self):
        a=PortClock(20,17);b=PortClock(20,17)
        a.shock(range(10));b.shock(range(10))
        a.advance(180,.002,.03)
        for stop in range(1,181):b.advance(stop,.002,.03)
        np.testing.assert_allclose(a.remaining,b.remaining,atol=1e-12)
        np.testing.assert_array_equal(a.up,b.up)
        self.assertEqual(len(a.events),len(b.events))
        np.testing.assert_allclose([x[0] for x in a.events],[x[0] for x in b.events],atol=1e-11)
    def test_hazard_rate_change_no_reset(self):
        c=PortClock(1,1,initial_up=[False]);c.remaining[0]=2.
        c.advance(1,0,.5);self.assertAlmostEqual(c.remaining[0],1.5)
        c.advance(2,0,1.);self.assertAlmostEqual(c.remaining[0],.5)
        c.advance(2.5,0,1.);self.assertTrue(c.up[0])
    def test_no_events_at_zero_rate(self):
        c=PortClock(2);s=c.advance(100,0,0)
        self.assertEqual(s,[(0.,100.,2)])
    def test_future_change_does_not_change_prefix(self):
        a=PortClock(4,5);b=PortClock(4,5)
        self.assertEqual(a.advance(50,.01,.02),b.advance(50,.01,.02))
        old=a.events.copy();b.shock([0]);b.advance(100,.01,.1)
        self.assertEqual(a.events,old)
    def test_tiny_mass_service_duration(self):
        for mass in [3.132786e-9,.01,.5,1.]:
            s=FractionalStation(150);s.arrive(Packet(1,mass,0,30,18));s.advance(20,40000)
            self.assertAlmostEqual(s.done[0][1],12.)
            self.assertAlmostEqual(s.served,mass*30,delta=max(1e-18,mass*1e-12))
    def test_fractional_fifo_split(self):
        s=FractionalStation();s.arrive(Packet(1,1.5,0,15,18));s.arrive(Packet(2,.5,0,15,18));s.advance(30,150)
        self.assertEqual([r[0] for r in s.start_ledger],[1,1,2])
        self.assertEqual([r[2] for r in s.start_ledger],[0,6,6])
        self.assertAlmostEqual(s.balances()['completed_veh'],2.)
        self.assertAlmostEqual(s.served,30.)
    def test_failed_station_preserves_commitment(self):
        s=FractionalStation();s.arrive(Packet(1,1,0,15,18));s.advance(3,150)
        s.advance(13,0);self.assertEqual(len(s.done),0);self.assertAlmostEqual(s.active[0].task,7.5)
        s.advance(20,150);self.assertAlmostEqual(s.done[0][1],16.)
    def test_vehicle_and_aggregate_caps(self):
        s=FractionalStation();s.arrive(Packet(1,20,0,10,18));s.advance(10,300)
        for a,b,p,m,e,each in s.intervals:
            self.assertLessEqual(e,p*(b-a)/60+1e-10);self.assertLessEqual(each,150+1e-10)
    def test_energy_and_mass_conservation(self):
        s=FractionalStation();s.arrive(Packet(1,1.123,0,15,18));s.advance(1,150)
        s.arrive(Packet(2,3.132786e-9,1,9,45));s.advance(30,150)
        for key in ['mass_residual','energy_residual']:self.assertLess(abs(s.balances()[key]),1e-12)
    def test_wcl_queue_not_energized(self):
        b,r,e=wcl_step(18,36,2,60,4)
        self.assertAlmostEqual(e,3.6)
        b2,r2,e2=wcl_step(b,r,0,60,0)
        self.assertEqual((b2,r2,e2),(b,r,0))
    def test_wcl_battery_limit(self):
        b,r,e=wcl_step(59,5,1,120,10)
        self.assertEqual((b,r,e),(60,3,2))
    def test_soc_infeasibility_is_not_penalty(self):
        with self.assertRaises(ValueError):wcl_step(12,0,.2,0,0)
    def test_ctm_mass_and_storage(self):
        n=np.array([10.,20.,5.]);q=np.ones(3)*4;jam=np.ones(3)*30
        for _ in range(20):
            new,f=ctm_chain_step(n,q,jam,np.ones(3),np.ones(3)*.5,1,3,2)
            self.assertAlmostEqual(new.sum(),n.sum()+f[0]-f[-1]);self.assertTrue(((new>=0)&(new<=jam)).all());n=new
    def test_ctm_cfl_rejected(self):
        with self.assertRaises(ValueError):ctm_chain_step([1],[1],[2],[1.1],[.5],1,1,1)
    def test_simplex_projection(self):
        p=project_simplex([3,-2,5],4);np.testing.assert_allclose(p,[1,0,3]);self.assertEqual(sum(p),4)
    def test_vi_known_solution(self):
        r=solve_vi(lambda x:np.array([2+2*x[0],5+x[1]]),[[0,1]],[10],[10,0],step=.4)
        self.assertTrue(r['converged']);np.testing.assert_allclose(r['flow'],[13/3,17/3],atol=2e-7)
        np.testing.assert_allclose(r['cost'],[2+2*r['flow'][0],5+r['flow'][1]])
    def test_vi_counts_all_positive_mass(self):
        r=vi_gap([1,3e-9],[1,math.inf],[[0,1]]);self.assertEqual(r['infeasible_mass'],3e-9);self.assertTrue(math.isinf(r['relative_gap']))
    def test_vi_exhaustion_is_not_pass(self):
        r=solve_vi(lambda x:np.array([2+2*x[0],5+x[1]]),[[0,1]],[10],[10,0],max_iter=1)
        self.assertFalse(r['converged'])
    def test_locked_prefix_order(self):
        c=[dict(links=[1,2,3],station=0),dict(links=[1,3,2],station=0),dict(links=[1,2,4],station=1)]
        self.assertEqual(locked_candidates([1],2,c),[0,2]);self.assertEqual(locked_candidates([1],2,c,0),[0])
    def test_pool_no_resource_creation(self):
        y=dispatch_pool([.3,.1,.6],2);self.assertAlmostEqual(y.sum(),2.)
        np.testing.assert_array_equal(dispatch_pool([0,0],2),[0,0])
    def test_pool_physical_delay(self):
        y=np.array([[1,0],[0,1],[1,0],[0,1.]])
        np.testing.assert_array_equal(delay_resource(y,2),[[0,0],[0,0],[1,0],[0,1]])
    def test_repair_game_known_solution(self):
        r=discrete_repair_game(lambda p:np.array([-(p[0]-1)**2,-(p[1]-2)**2]),[[0,1,2],[0,1,2]],[0,0])
        self.assertEqual(r['profile'],(1,2));self.assertTrue(r['grid_nash'])
    def test_repair_game_cycle_not_nash(self):
        r=discrete_repair_game(lambda p:np.array([1 if p[0]==p[1] else -1,-1 if p[0]==p[1] else 1]),[[0,1],[0,1]],[0,0])
        self.assertFalse(r['grid_nash'])
    def test_weighted_quantile(self):
        self.assertEqual(weighted_quantile([1,10],[99,1],.95),1)
        self.assertEqual(weighted_quantile([1,10],[99,1],1.),10)
    def test_recovery_right_censoring(self):
        t=np.arange(21);p=np.r_[np.zeros(18),np.ones(3)]
        r,c=recovery_time(t,p,0,hold=5);self.assertTrue(c);self.assertTrue(math.isnan(r))
    def test_recovery_hold(self):
        r,c=recovery_time(np.arange(21),np.r_[np.zeros(5),np.ones(16)],2,hold=10)
        self.assertEqual((r,c),(3.,False))

if __name__=='__main__':unittest.main(verbosity=2)
