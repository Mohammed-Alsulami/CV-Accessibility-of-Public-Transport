import React, { useRef, useState } from "react";

export default function HomePage() {
  const fileInputRef = useRef(null);

  const [file, setFile] = useState(null);
  const [preview, setPreview] = useState(null);
  const [report, setReport] = useState(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(null);
  const [showDsaptInfo, setShowDsaptInfo] = useState(false);

  const handleUploadClick = () => fileInputRef.current.click();

  const handleFileChange = (e) => {
    const f = e.target.files?.[0];
    if (!f) return;

    setFile(f);
    setPreview(URL.createObjectURL(f));
    setReport(null);
    setError(null);
  };

  const handleAnalyse = async () => {
    if (!file) return alert("Upload an image first");

    setLoading(true);
    setError(null);

    try {
      const formData = new FormData();
      formData.append("file", file);

      let res;
      try {
        res = await fetch("http://127.0.0.1:8000/analyze", {
          method: "POST",
          headers: {
          "x-api-key": "dev-secret-key",
          },
          body: formData,

        });
      } catch {
        throw new Error(
          "Could not reach the backend. Make sure the server is running on http://127.0.0.1:8000"
        );
      }

      const data = await res.json();
      if (!res.ok) throw new Error(data.detail || "Analysis failed");

      setReport(data);
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div style={styles.page}>

      {/* HEADER */}
      <header style={styles.header}>
        <div style={styles.headerInner}>
          <img src="/white-logo.png" style={styles.logo} alt="logo" />
          <div style={styles.title}>Accessibility Audit Tool</div>
        </div>
      </header>

      {/* MAIN */}
      <main style={styles.container}>

        {/* UPLOAD CARD */}
        <section style={styles.card}>
          <h2 style={styles.h2}>Analyse Infrastructure</h2>
          <p style={styles.subtext}>
            Upload an image in order to identify tactile flooring and assess its
            compliance with DSAPT standards.
          </p>

          <div onClick={handleUploadClick} style={styles.uploadBox}>
            <input
              ref={fileInputRef}
              type="file"
              accept="image/*,video/*"
              hidden
              onChange={handleFileChange}
            />
            {!preview ? (
              <div style={styles.uploadState}>Click to upload image or video</div>
            ) : (
              <img src={preview} style={styles.preview} alt="preview" />
            )}
          </div>

          <button
            onClick={handleAnalyse}
            disabled={loading}
            style={{ ...styles.button, ...(loading ? styles.buttonDisabled : {}) }}
          >
            {loading ? "Analysing…" : "Run Analysis"}
          </button>

          {error && <div style={styles.error}>{error}</div>}
        </section>

        {/* RESULTS CARD */}
        {report && (
          <section style={styles.card}>
            <h2 style={styles.h2}>Results</h2>

{showDsaptInfo && (
  <div style={styles.popupOverlay}>
    <div style={styles.dsaptPopup}>
      <button
        type="button"
        onClick={() => setShowDsaptInfo(false)}
        style={styles.popupClose}
      >
        ×
      </button>

      <h3 style={styles.popupTitle}>DSAPT Contrast Requirements</h3>

      <p style={styles.popupText}>
        This tool checks the luminance contrast between the detected tactile
        flooring and the surrounding floor surface.
      </p>

      <div style={styles.requirementList}>
        <div><strong>Below 30%</strong>: Not compatible</div>
        <div><strong>30% to 44.99%</strong>: Minimum compatibility</div>
        <div><strong>45% to 59.99%</strong>: Moderate compatibility</div>
        <div><strong>60% or above</strong>: High compatibility</div>
      </div>

      <p style={styles.popupText}>
        The DSAPT score shown in the results is calculated based on these
        contrast levels.
      </p>
    </div>
  </div>
)}

            {/* SCORES */}
            <div style={styles.scoreGrid}>
              <div style={styles.scoreBox}>
                <div style={styles.scoreLabel}>Tactile Flooring</div>
                <div
                  style={{
                    ...styles.scoreValue,
                    color: report.has_tactile_flooring ? "#16a34a" : "#dc2626",
                  }}
                >
                  {report.has_tactile_flooring ? "Detected" : "Not Detected"}
                </div>
              </div>

              <div style={styles.scoreBox}>
                <div style={styles.scoreLabelWithIcon}>
                  <span>DSAPT Score</span>
                  <button
                   type="button"
                   onClick={() => setShowDsaptInfo(true)}
                   style={styles.infoIcon}
                   title="View DSAPT contrast requirements"
                  >
                   👁
                  </button>
              </div>

              <div style={styles.scoreValue}>{report.compatibility_percentage}%</div>
            </div>
            
              <div style={styles.scoreBox}>
                <div style={styles.scoreLabel}>Compatibility</div>
                <div style={styles.scoreValue}>{report.compatibility_label}</div>
              </div>

              <div style={styles.scoreBox}>
                <div style={styles.scoreLabel}>Contrast</div>
                <div style={styles.scoreValue}>
                  {report.contrast_percentage?.toFixed(1)}%
                </div>
              </div>
            </div>

            {/* ASSESSMENT NOTES */}
            <div style={styles.notes}>
              <strong>Assessment Notes</strong>
              <p style={{ marginTop: 6, lineHeight: 1.7 }}>{report.notes}</p>
            </div>

            {/* INPUT + OUTPUT IMAGES */}
            {(report.input_image || report.output_image) && (
              <div>
                <h3 style={styles.h3}>Image Analysis</h3>
                <div style={styles.imageGrid}>
                  {report.input_image && (
                    <div style={styles.imageBlock}>
                      <div style={styles.imageLabel}>Original Image</div>
                      <img
                        src={`data:image/jpeg;base64,${report.input_image}`}
                        alt="Original"
                        style={styles.resultImage}
                      />
                    </div>
                  )}
                  {report.output_image && (
                    <div style={styles.imageBlock}>
                      <div style={styles.imageLabel}>Processed Output</div>
                      <img
                        src={`data:image/png;base64,${report.output_image}`}
                        alt="Processed"
                        style={styles.resultImage}
                      />
                    </div>
                  )}
                </div>
              </div>
            )}

            {/* PDF DOWNLOAD */}
            {report.report_pdf && (
              <a
                href={`data:application/pdf;base64,${report.report_pdf}`}
                download="DSAPT_Report.pdf"
                style={styles.downloadButton}
              >
                Download PDF Report
              </a>
            )}
          </section>
        )}

        {/* ABOUT CARD */}
        <section style={styles.card}>
          <h2 style={styles.h2}>About this project</h2>
          <p style={styles.subtext}>
            This project was developed as part of a university initiative focused
            on applying AI to real-world accessibility challenges. It reflects a
            commitment to improving accessibility and supporting people with
            disabilities, with the broader aim of contributing to more inclusive
            public spaces. In this context, the project explores how technology
            can support greater independence and inclusion in everyday travel.
            <br /><br />
            The system is a proof-of-concept tool that uses computer vision to
            analyse public transport infrastructure and identify accessibility
            features and potential barriers. By processing images or video, it
            generates a structured, human-readable report to assist with
            accessibility assessment.
            <br /><br />
            As an early-stage prototype, the system has a number of limitations.
            Detection accuracy is influenced by factors such as image quality,
            lighting, and camera angles. In addition, some features may still
            require manual verification, and the tool is not intended to replace
            formal compliance assessments.
          </p>
        </section>

      </main>

      {/* FOOTER */}
      <footer style={styles.footer}>
        <div style={styles.footerInner}>
          <div style={styles.footerTitle}>About us</div>
          <div style={styles.footerText}>
            This project was developed by a small team of university students
            passionate about accessibility and inclusive design. Combining skills
            in AI, computer vision, and software development, the team set out to
            explore practical ways technology can improve everyday public transport
            experiences. Their goal is to create tools that support greater
            independence and accessibility for all users.
          </div>
        </div>
      </footer>

    </div>
  );
}

/* ---------------- STYLES ---------------- */

const styles = {
  page: {
    fontFamily: "Arial",
    background: "#f8fafc",
    overflowX: "hidden",
  },

  header: {
    background: "#212121",
    color: "#fff",
    borderBottom: "1px solid #111827",
  },

  headerInner: {
    maxWidth: 1100,
    margin: "0 auto",
    display: "grid",
    gridTemplateColumns: "1fr auto 1fr",
    alignItems: "center",
    padding: "14px 16px",
  },

  logo: {
    height: 28,
    objectFit: "contain",
  },

  title: {
    textAlign: "center",
    fontWeight: 700,
    fontSize: 18,
    color: "#ffffff",
  },

  container: {
    maxWidth: 1100,
    margin: "0 auto",
    padding: 20,
    display: "flex",
    flexDirection: "column",
    gap: 18,
  },

  card: {
    background: "#fff",
    border: "1px solid #e5e7eb",
    borderRadius: 16,
    padding: 24,
  },

  h2: {
    fontSize: 17,
    fontWeight: 600,
    marginBottom: 10,
  },

  h3: {
    fontSize: 15,
    fontWeight: 600,
    margin: "20px 0 12px",
  },

  subtext: {
    fontSize: 14.5,
    color: "#4b5563",
    lineHeight: 1.6,
  },

  uploadBox: {
    height: 260,
    background: "#f1f5f9",
    border: "1px dashed #cbd5e1",
    borderRadius: 14,
    display: "flex",
    alignItems: "center",
    justifyContent: "center",
    cursor: "pointer",
    overflow: "hidden",
    marginTop: 12,
  },

  uploadState: { color: "#64748b" },

  preview: {
    width: "100%",
    height: "100%",
    objectFit: "cover",
  },

  button: {
    marginTop: 12,
    width: "100%",
    padding: 11,
    background: "#2563eb",
    color: "#fff",
    border: 0,
    borderRadius: 10,
    fontWeight: 600,
    cursor: "pointer",
    fontSize: 15,
  },

  buttonDisabled: {
    background: "#93c5fd",
    cursor: "not-allowed",
  },

  error: {
    marginTop: 10,
    background: "#fee2e2",
    color: "#b91c1c",
    padding: "10px 14px",
    borderRadius: 10,
    fontSize: 14,
  },

  /* Score grid */
  scoreGrid: {
    display: "grid",
    gridTemplateColumns: "repeat(auto-fit, minmax(140px, 1fr))",
    gap: 12,
    marginBottom: 20,
  },

  scoreBox: {
    background: "#f8fafc",
    border: "1px solid #e5e7eb",
    borderRadius: 12,
    padding: "14px 16px",
    textAlign: "center",
  },

  scoreLabel: {
    fontSize: 12,
    color: "#6b7280",
    marginBottom: 6,
    fontWeight: 500,
  },

  scoreValue: {
    fontSize: 17,
    fontWeight: 700,
    color: "#111827",
  },

  notes: {
    background: "#f8fafc",
    border: "1px solid #e5e7eb",
    borderRadius: 12,
    padding: "14px 16px",
    fontSize: 14,
    color: "#374151",
    marginBottom: 4,
  },

  /* Image grid */
  imageGrid: {
    display: "grid",
    gridTemplateColumns: "1fr 1fr",
    gap: 16,
  },

  imageBlock: {
    display: "flex",
    flexDirection: "column",
    gap: 8,
  },

  imageLabel: {
    fontSize: 13,
    fontWeight: 600,
    color: "#6b7280",
    textAlign: "center",
  },

  resultImage: {
    width: "100%",
    borderRadius: 10,
    border: "1px solid #d1d5db",
    objectFit: "cover",
  },

  /* PDF button */
  downloadButton: {
    display: "inline-block",
    marginTop: 20,
    padding: "12px 20px",
    background: "#16a34a",
    color: "#fff",
    borderRadius: 10,
    textDecoration: "none",
    fontWeight: 600,
    fontSize: 14,
  },

  /* FOOTER */
  footer: {
    marginTop: 30,
    background: "#212121",
    color: "#e5e7eb",
    padding: "28px 16px",
  },

  footerInner: {
    maxWidth: 1100,
    margin: "0 auto",
  },

  footerTitle: {
    fontWeight: 700,
    marginBottom: 10,
    color: "#ffffff",
  },

  footerText: {
    fontSize: 14.5,
    lineHeight: 1.7,
    color: "#d1d5db",
  },


   scoreLabelWithIcon: {
  fontSize: 12,
  color: "#6b7280",
  marginBottom: 6,
  fontWeight: 500,
  display: "flex",
  alignItems: "center",
  justifyContent: "center",
  gap: 6,
},

infoIcon: {
  border: "none",
  background: "transparent",
  cursor: "pointer",
  fontSize: 15,
  padding: 0,
  lineHeight: 1,
},

popupOverlay: {
  position: "fixed",
  top: 0,
  left: 0,
  width: "100%",
  height: "100%",
  background: "rgba(0, 0, 0, 0.35)",
  display: "flex",
  alignItems: "center",
  justifyContent: "center",
  zIndex: 1000,
},

dsaptPopup: {
  background: "#ffffff",
  width: 430,
  maxWidth: "90%",
  borderRadius: 16,
  padding: 24,
  boxShadow: "0 10px 30px rgba(0, 0, 0, 0.18)",
  position: "relative",
},

popupClose: {
  position: "absolute",
  top: 10,
  right: 14,
  border: "none",
  background: "transparent",
  fontSize: 26,
  cursor: "pointer",
  color: "#374151",
},

popupTitle: {
  fontSize: 17,
  fontWeight: 700,
  marginBottom: 12,
  color: "#111827",
},

popupText: {
  fontSize: 14,
  color: "#4b5563",
  lineHeight: 1.6,
},

requirementList: {
  background: "#f8fafc",
  border: "1px solid #e5e7eb",
  borderRadius: 12,
  padding: 14,
  fontSize: 14,
  color: "#374151",
  lineHeight: 1.8,
  margin: "12px 0",
},
};