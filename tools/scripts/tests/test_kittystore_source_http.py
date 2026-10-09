from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]

class KittyStoreSourceHTTPTests(unittest.TestCase):
    def test_http_failure_precedes_json_decode_and_does_not_dump_payload(self):
        source = (ROOT / 'ThirdParty/SideStore/Source/AltStore/Operations/FetchSourceOperation.swift').read_text()
        start = source.index('if let httpResponse = response as? HTTPURLResponse')
        end = source.index('let decoder = AltStoreCore.JSONDecoder()', start)
        boundary = source[start:end]
        self.assertIn('!(200...299).contains(httpResponse.statusCode)', boundary)
        self.assertIn('URLError.badServerResponse.rawValue', boundary)
        self.assertIn('HTTP \\(httpResponse.statusCode)', boundary)
        self.assertNotIn('sourceURL.absoluteString', boundary)
        self.assertNotIn('String(data:', boundary)
        self.assertNotIn('print(', boundary)
        self.assertLess(start, source.index('source = try decoder.decode(Source.self, from: data)'))

if __name__ == '__main__':
    unittest.main()
