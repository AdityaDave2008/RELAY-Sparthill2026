import { PrintCard, PrintNotice, Volunteer } from './analog/Analog.tsx';
import { api } from './api/index.ts';
import { Coordinator } from './coordinator/Coordinator.tsx';
import { Resident } from './resident/Resident.tsx';
import { SimulationBanner, TopBar, usePoll, useRoute } from './ui/common.tsx';
import { useDevice } from './device/device.ts';
import { Icon } from './ui/icons.tsx';

export function App() {
  const d = useDevice();
  return <>{(d.storageError || d.loadError) && <div className="banner warn" role="alert">{d.storageError || d.loadError}</div>}<Routes /></>;
}

function Routes() {
  const [section, ...rest] = useRoute();
  switch (section) {
    case 'resident':
      return <Resident path={rest} />;
    case 'coordinator':
      return <Coordinator />;
    case 'volunteer':
      return <Volunteer key={rest[0]} zoneId={rest[0]} />;
    case 'print':
      return rest[0] === 'card' ? <PrintCard zoneId={rest[1] ?? 'north-hills'} /> : <PrintNotice zoneId={rest[1] ?? 'north-hills'} />;
    case 'architecture':
      return <Architecture />;
    default:
      return <Home />;
  }
}

function Home() {
  return (
    <>
      <TopBar />
      <main className="page stack-lg" style={{ maxWidth: 900 }}>
        <div className="stack">
          <h1 style={{ fontSize: '2rem' }}>Emergency information that keeps moving when the network doesn't.</h1>
          <p className="muted" style={{ fontSize: '1.05rem' }}>
            When a disaster takes out cell service, the people cut off are the ones who most need to know where water, food, medicine and
            shelter are. RELAY carries warnings in and requests for help out, from phone to phone, over radio, and on paper. Amazon
            Bedrock turns messy field reports into clear, translated instructions.
          </p>
        </div>
        <div className="roles">
          <a className="role-card" href="#/resident">
            <Icon name="phone" />
            <h2>Resident</h2>
            <p className="small muted">No signal. Receive warnings, ask for help, see when it's answered.</p>
          </a>
          <a className="role-card" href="#/coordinator">
            <Icon name="map" />
            <h2>Coordinator</h2>
            <p className="small muted">Sees requests arrive, uses Bedrock to understand and answer them, and publishes warnings.</p>
          </a>
          <a className="role-card" href="#/volunteer">
            <Icon name="paper" />
            <h2>Volunteer</h2>
            <p className="small muted">Delivers printed notices and spoken updates to people without phones, and brings back paper help cards.</p>
          </a>
          <a className="role-card" href="#/architecture">
            <Icon name="sparkle" />
            <h2>How it works</h2>
            <p className="small muted">Architecture and where Amazon Bedrock fits.</p>
          </a>
        </div>
        <SimulationBanner>All places, people, and agencies in this demo are fictional. The government approval step is simulated.</SimulationBanner>
        {api.mode === 'mock' && <p className="small muted">MOCK AI mode is explicitly enabled. Disable VITE_MOCK_API to test the live Amazon Bedrock workflow.</p>}
      </main>
    </>
  );
}

function Architecture() {
  const [health] = usePoll(() => api.health(), 30_000);
  return (
    <>
      <TopBar role="Architecture" />
      <main className="page stack-lg" style={{ maxWidth: 980 }}>
        <h1>How RELAY works</h1>
        <div className="arch">
          <div className="arch-row">
            <div className="arch-box">
              <h3>Resident phone (offline)</h3>
              <p className="small">Web app with saved messages. Creates help requests with GPS accuracy, and shows warnings and replies.</p>
            </div>
            <div className="arch-box">
              <h3>Volunteer phone</h3>
              <p className="small">Carries messages between areas with and without signal (store and forward). Enters paper help cards.</p>
            </div>
            <div className="arch-box">
              <h3>No device</h3>
              <p className="small">Printed pictogram notices, spoken announcements, and paper help cards.</p>
            </div>
          </div>
          <p className="arch-arrow">⇅ nearby transfer (QR / local) · hop limits, expiry, duplicate checks (@relay/core)</p>
          <div className="arch-row">
            <div className="arch-box">
              <h3>Gateway sync</h3>
              <p className="small">When any carrier reaches signal: upload batches, download warnings and replies for every device it carries for.</p>
            </div>
          </div>
          <p className="arch-arrow">⇅ HTTPS</p>
          <div className="arch-row">
            <div className="arch-box aws">
              <h3>Message API</h3>
              <p className="small">The local demo API stores messages, sends replies to the right device, and publishes approved warnings. AWS Lambda deployment source is included.</p>
            </div>
            <div className="arch-box aws" style={{ gridColumn: '1 / -1', borderWidth: 2 }}>
              <h3>Amazon Bedrock, at the centre of every path</h3>
              <ol className="small" style={{ margin: '4px 0 0', paddingLeft: 18, lineHeight: 1.6 }}>
                <li><strong>Reads every request</strong>: pulls needs, number of people and location out of messy text.</li>
                <li><strong>Reads paper help cards</strong>: vision turns a photo of a returned card into a request.</li>
                <li><strong>Situation brief</strong>: ranks all open requests and flags areas that have gone silent.</li>
                <li><strong>Writes replies</strong>: based only on the coordinator's notes, in the resident's language.</li>
                <li><strong>Writes warnings</strong>: plain language, translations, printable notice and radio script.</li>
              </ol>
            </div>
            <div className="arch-box aws">
              <h3>{health?.storage === 'dynamodb' ? 'Amazon DynamoDB · connected' : 'Durable message storage'}</h3>
              <p className="small">{health?.storage === 'dynamodb' ? 'This running app stores messages and AI analysis in Amazon DynamoDB, with conditional writes to prevent duplicate uploads.' : 'The API uses file storage unless configured for Amazon DynamoDB. The AWS deployment includes conditional writes to prevent duplicate uploads.'}</p>
            </div>
          </div>
          <p className="arch-arrow">⇅</p>
          <div className="arch-row">
            <div className="arch-box">
              <h3>Coordinator dashboard</h3>
              <p className="small">A person reviews AI output, answers requests, and approves warnings (simulated approval).</p>
            </div>
          </div>
        </div>
        <div className="card stack">
          <h2>Responsible AI</h2>
          <ul className="small" style={{ margin: 0, paddingLeft: 18, lineHeight: 1.6 }}>
            <li>Bedrock never sends anything by itself. A coordinator reviews every warning and reply.</li>
            <li>AI output is labelled and marked "requires human review". If Bedrock fails, the request is kept.</li>
            <li>Delivery states show only what actually happened: saved, relayed, uploaded, acknowledged.</li>
          </ul>
        </div>
      </main>
    </>
  );
}
