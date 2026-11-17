import unittest
from network import *

class NetworkTests(unittest.TestCase):
    def network(self):
        return [Link(1,1,2,'ROAD',2,2,1),Link(2,2,3,'WCL',2,2,1,60),
                Link(3,3,4,'FCS',station=0),Link(4,4,5,'EXIT',1,0)]
    def test_route_mass_energy(self):
        p=[Traveler(1,2.5,0,(1,2,3,4),18,9),Traveler(2,3.132786e-9,1,(1,2,3,4),45,9)]
        r=load_fixed_flow(self.network(),p,60,lambda s,t:300)
        self.assertLess(abs(r['mass_residual']),1e-12);self.assertLess(r['fcs_energy_residual'],1e-11)
        self.assertEqual(r['infeasible'],[]);self.assertEqual(r['uncompleted_mass'],0)
        self.assertAlmostEqual(sum(x.mass for x,t in r['completed']),2.500000003132786)
        for p,t in r['completed']:self.assertAlmostEqual(p.battery,18+9-.8 if p.id==1 else 45+9-.8)
    def test_road_clock_and_fifo(self):
        r=load_fixed_flow(self.network(),[Traveler(1,3,0,(1,2,3,4),18,9),Traveler(2,1,1,(1,2,3,4),18,9)],60,lambda s,t:300)
        for lid in [1,2]:
            rows=[x for x in r['trace'] if x['link']==lid]
            self.assertEqual([x['id'] for x in rows],[1,1,1,2])
            self.assertTrue(all(x['exit']-x['entry']>=2 for x in rows))
    def test_no_wcl_in_downstream_queue(self):
        r=load_fixed_flow(self.network(),[Traveler(1,3,0,(1,2,3,4),18,9)],60,lambda s,t:300)
        e=sum(x['wcl_kwh'] for x in r['timeseries']);self.assertAlmostEqual(e,3*1.8)
    def test_missing_discharge_rejected(self):
        with self.assertRaises(ValueError):load_fixed_flow([Link(1,1,2,'ROAD',discharge_veh_min=0)],[],10,lambda s,t:1)
    def test_broken_topology_rejected(self):
        with self.assertRaises(ValueError):load_fixed_flow(self.network(),[Traveler(1,1,0,(1,3),18,9)],10,lambda s,t:1)
    def test_unfinished_not_completed(self):
        r=load_fixed_flow(self.network(),[Traveler(1,1,0,(1,2,3,4),18,9)],5,lambda s,t:0)
        self.assertEqual(r['completed'],[]);self.assertEqual(r['uncompleted_mass'],1.)
        self.assertAlmostEqual(r['mass_residual'],0)

if __name__=='__main__':unittest.main(verbosity=2)
