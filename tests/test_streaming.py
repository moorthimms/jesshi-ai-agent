import sys
import unittest
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'native'))
from streaming import respond
from voice_worker import strip_wake

class StreamTests(unittest.TestCase):
    def test_streams_before_completion_and_uses_short_warm_non_thinking_request(self):
        events=[];payloads=[]
        def packets(payload):
            payloads.append(payload)
            yield {'message': {'content':'Hello, this is '}}
            self.assertIn('delta',[x[0] for x in events])
            yield {'message':{'content':'a short reply. '}}
            self.assertIn('speech',[x[0] for x in events])
            yield {'message':{'content':'Done.'},'done':True,'eval_count':8}
        messages=[{'role':'user','content':'Hi'}]
        answer=respond(messages,'local',set(),False,False,lambda kind,**kw:events.append((kind,kw)),source=packets)
        self.assertEqual(answer,'Hello, this is a short reply. Done.')
        self.assertFalse(payloads[0]['think']);self.assertTrue(payloads[0]['stream'])
        self.assertEqual(payloads[0]['keep_alive'],'15m')
        self.assertEqual(payloads[0]['options']['num_predict'],256)
        self.assertNotIn('tools',payloads[0])

    @patch('assistant.execute')
    def test_undeclared_model_tool_cannot_execute(self,execute):
        count=0
        def packets(payload):
            nonlocal count
            count+=1
            yield {'message':{'tool_calls':[{'function':{'name':'open_app','arguments':{'name':'calculator'}}}]}} if count==1 else {'message':{'content':'Blocked.'}}
        messages=[{'role':'user','content':'Open Calculator'}]
        respond(messages,'local',set(),False,False,lambda *a,**kw:None,source=packets)
        execute.assert_not_called()
        self.assertIn('blocked',messages[2]['content'].lower())

    def test_wake_phrase_variants_and_tail(self):
        for text in ['Hi Jessy, what time is it?', 'Hey Jessie what time is it?', 'Hello Jesse. what time is it?']:
            self.assertEqual(strip_wake(text),'what time is it?')
        self.assertIsNone(strip_wake('Tell me about Jesse James'))
        self.assertIsNone(strip_wake('Hello everyone'))
