import { useCallback, useEffect, useState } from "react";
import axios from "axios";
import {
  Activity,
  AlertCircle,
  ArrowDownRight,
  ArrowUpRight,
  CalendarDays,
  RefreshCw,
  Ruler,
  Shirt,
  Users,
} from "lucide-react";
import {
  Bar,
  BarChart,
  CartesianGrid,
  Cell,
  Line,
  LineChart,
  Pie,
  PieChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";

const API_URL = "https://fitscan-api-901w.onrender.com/api/dashboard/stats";
const ACCENT = "#7C4DFF";
const PIE_COLORS = ["#7C4DFF", "#32D6C5", "#FFB74D", "#F06292", "#64B5F6"];

const numberFormat = new Intl.NumberFormat("en-IN");
const dateLabel = (value) =>
  new Date(`${value}T00:00:00`).toLocaleDateString("en-IN", {
    weekday: "short",
    day: "numeric",
  });

function MetricCard({ icon: Icon, label, value, helper, trend }) {
  return (
    <article className="metric-card panel">
      <div className="metric-topline">
        <span className="metric-icon">
          <Icon size={19} />
        </span>
        {trend ? (
          <span className="trend">
            <ArrowUpRight size={14} /> Live
          </span>
        ) : null}
      </div>
      <p className="metric-label">{label}</p>
      <div className="metric-value">{value}</div>
      <p className="metric-helper">{helper}</p>
    </article>
  );
}

function ChartCard({ title, subtitle, children, className = "" }) {
  return (
    <section className={`chart-card panel ${className}`}>
      <div className="chart-heading">
        <div>
          <h2>{title}</h2>
          <p>{subtitle}</p>
        </div>
        <span className="chart-menu" aria-hidden="true">
          •••
        </span>
      </div>
      {children}
    </section>
  );
}

function ChartTooltip({ active, payload, label, valueLabel = "Scans" }) {
  if (!active || !payload?.length) return null;
  return (
    <div className="chart-tooltip">
      <span>{label}</span>
      <strong>
        {numberFormat.format(payload[0].value)} {valueLabel.toLowerCase()}
      </strong>
    </div>
  );
}

export default function App() {
  const [stats, setStats] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [lastUpdated, setLastUpdated] = useState(null);

  const loadStats = useCallback(async () => {
    setLoading(true);
    setError("");
    try {
      // Render free tier can sleep for ~15 minutes; the first request may take
      // up to a minute while the service cold-starts. Give it a generous window.
      const response = await axios.get(API_URL, { timeout: 60000 });
      setStats(response.data);
      setLastUpdated(new Date());
    } catch (requestError) {
      setError(
        requestError.response
          ? `The analytics API returned ${requestError.response.status}.`
          : "Could not reach the analytics API. The server may be waking up from sleep - try again in a moment.",
      );
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    loadStats();
  }, [loadStats]);

  const lineData = (stats?.scans_over_last_7_days ?? []).map((item) => ({
    ...item,
    day: dateLabel(item.date),
  }));
  const sizeData = stats?.size_distribution ?? [];
  const fitData = stats?.fit_preferences ?? [];
  const totalFitScans = fitData.reduce((sum, item) => sum + item.value, 0);

  return (
    <main className="dashboard-shell">
      <div className="dashboard-content">
        <header className="topbar">
          <div className="brand-lockup">
            <div className="brand-mark">
              <Ruler size={22} strokeWidth={2.4} />
            </div>
            <div>
              <p className="eyebrow">FITSCAN AI</p>
              <h1>Merchant Analytics</h1>
            </div>
          </div>
          <div className="topbar-actions">
            <div className="date-chip">
              <CalendarDays size={16} /> Last 7 days
            </div>
            <button
              className="refresh-button"
              onClick={loadStats}
              disabled={loading}
            >
              <RefreshCw size={16} className={loading ? "spin" : ""} />
              <span>Refresh</span>
            </button>
            <div className="avatar" title="Merchant">
              M
            </div>
          </div>
        </header>

        <section className="welcome-row">
          <div>
            <p className="eyebrow accent-text">OVERVIEW</p>
            <h2>Store performance</h2>
            <p className="welcome-copy">
              A clear view of customer scans and fit recommendations.
            </p>
          </div>
          {lastUpdated && (
            <span className="updated-label">
              Updated{" "}
              {lastUpdated.toLocaleTimeString("en-IN", {
                hour: "2-digit",
                minute: "2-digit",
              })}
            </span>
          )}
        </section>

        {error && (
          <div className="error-banner" role="alert">
            <AlertCircle size={19} />
            <span>{error}</span>
            <button onClick={loadStats}>Try again</button>
          </div>
        )}

        <section className="metrics-grid" aria-label="Key metrics">
          <MetricCard
            icon={Users}
            label="Total Scans Today"
            value={
              loading && !stats
                ? "—"
                : numberFormat.format(stats?.total_scans_today ?? 0)
            }
            helper="Completed customer scans"
            trend
          />
          <MetricCard
            icon={Shirt}
            label="Most Popular Size"
            value={loading && !stats ? "—" : (stats?.most_popular_size ?? "—")}
            helper={
              stats?.most_popular_size
                ? "Leading recommendation overall"
                : "No size data yet"
            }
          />
          <MetricCard
            icon={Activity}
            label="Total Scans"
            value={
              loading && !stats
                ? "—"
                : numberFormat.format(stats?.total_scans ?? 0)
            }
            helper="All recorded customers"
          />
        </section>

        {loading && !stats ? (
          <section className="loading-grid" aria-label="Loading analytics">
            <div className="loading-panel panel" />
            <div className="loading-panel panel" />
            <div className="loading-panel panel" />
          </section>
        ) : (
          <section className="charts-grid">
            <ChartCard
              title="Customer Scans Over Time"
              subtitle="Daily completed scans · last 7 days"
              className="wide-chart"
            >
              <div className="chart-area line-area">
                <ResponsiveContainer width="100%" height="100%">
                  <LineChart
                    data={lineData}
                    margin={{ top: 14, right: 12, left: -16, bottom: 0 }}
                  >
                    <CartesianGrid
                      stroke="#292832"
                      strokeDasharray="4 6"
                      vertical={false}
                    />
                    <XAxis
                      dataKey="day"
                      axisLine={false}
                      tickLine={false}
                      tick={{ fill: "#8D8B99", fontSize: 12 }}
                      dy={10}
                    />
                    <YAxis
                      allowDecimals={false}
                      axisLine={false}
                      tickLine={false}
                      tick={{ fill: "#777582", fontSize: 11 }}
                    />
                    <Tooltip content={<ChartTooltip />} />
                    <Line
                      type="monotone"
                      dataKey="scans"
                      name="Scans"
                      stroke={ACCENT}
                      strokeWidth={3}
                      dot={{
                        r: 4,
                        fill: ACCENT,
                        stroke: "#17161d",
                        strokeWidth: 2,
                      }}
                      activeDot={{
                        r: 6,
                        fill: ACCENT,
                        stroke: "#fff",
                        strokeWidth: 2,
                      }}
                    />
                  </LineChart>
                </ResponsiveContainer>
              </div>
            </ChartCard>

            <ChartCard
              title="Recommended Size Distribution"
              subtitle="Most selected sizes"
            >
              <div className="chart-area">
                {sizeData.length ? (
                  <ResponsiveContainer width="100%" height="100%">
                    <BarChart
                      data={sizeData}
                      margin={{ top: 10, right: 2, left: -22, bottom: 0 }}
                    >
                      <CartesianGrid
                        stroke="#292832"
                        strokeDasharray="4 6"
                        vertical={false}
                      />
                      <XAxis
                        dataKey="name"
                        axisLine={false}
                        tickLine={false}
                        tick={{ fill: "#A7A5B1", fontSize: 12 }}
                        dy={8}
                      />
                      <YAxis
                        allowDecimals={false}
                        axisLine={false}
                        tickLine={false}
                        tick={{ fill: "#777582", fontSize: 11 }}
                      />
                      <Tooltip
                        content={<ChartTooltip valueLabel="Scans" />}
                        cursor={{ fill: "#ffffff0a" }}
                      />
                      <Bar
                        dataKey="value"
                        name="Scans"
                        fill={ACCENT}
                        radius={[6, 6, 0, 0]}
                        maxBarSize={42}
                      />
                    </BarChart>
                  </ResponsiveContainer>
                ) : (
                  <EmptyChart message="Size recommendations will appear here." />
                )}
              </div>
            </ChartCard>

            <ChartCard title="Fit Preferences" subtitle="Recommendation mix">
              <div className="chart-area pie-area">
                {fitData.length ? (
                  <>
                    <ResponsiveContainer width="100%" height="100%">
                      <PieChart>
                        <Pie
                          data={fitData}
                          dataKey="value"
                          nameKey="name"
                          innerRadius={63}
                          outerRadius={91}
                          paddingAngle={4}
                          stroke="none"
                        >
                          {fitData.map((item, index) => (
                            <Cell
                              key={item.name}
                              fill={PIE_COLORS[index % PIE_COLORS.length]}
                            />
                          ))}
                        </Pie>
                        <Tooltip
                          content={<ChartTooltip valueLabel="Scans" />}
                        />
                      </PieChart>
                    </ResponsiveContainer>
                    <div className="pie-center">
                      <strong>{numberFormat.format(totalFitScans)}</strong>
                      <span>scans</span>
                    </div>
                  </>
                ) : (
                  <EmptyChart message="Fit preferences will appear here." />
                )}
              </div>
              <div className="legend-list">
                {fitData.map((item, index) => (
                  <div className="legend-row" key={item.name}>
                    <span className="legend-name">
                      <i
                        style={{
                          background: PIE_COLORS[index % PIE_COLORS.length],
                        }}
                      />
                      {item.name}
                    </span>
                    <strong>
                      {totalFitScans
                        ? Math.round((item.value / totalFitScans) * 100)
                        : 0}
                      %
                    </strong>
                  </div>
                ))}
              </div>
            </ChartCard>
          </section>
        )}

        <footer className="dashboard-footer">
          <span>FitScan AI · Merchant workspace</span>
          <span>
            <ArrowDownRight size={13} /> Analytics are based on scans recorded
            by the mobile app.
          </span>
        </footer>
      </div>
    </main>
  );
}

function EmptyChart({ message }) {
  return (
    <div className="empty-chart">
      <span>
        <Activity size={20} />
      </span>
      <p>{message}</p>
    </div>
  );
}
