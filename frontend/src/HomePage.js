import React, { useRef, useState } from "react";

export default function HomePage() {
  const fileInputRef = useRef(null);

  const [file, setFile] = useState(null);
  const [preview, setPreview] = useState(null);
  const [report, setReport] = useState(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(null);

  // OPEN FILE PICKER
  const handleUploadClick = () => {
    fileInputRef.current.click();
  };

  // FILE SELECT
  const handleFileChange = (e) => {
    const selectedFile = e.target.files[0];

    if (!selectedFile) return;

    setFile(selectedFile);
    setPreview(URL.createObjectURL(selectedFile));
    setReport(null);
    setError(null);

    console.log("📁 FILE SELECTED:", selectedFile.name);
  };

  // 🔥 ANALYSE FUNCTION (FULL DEBUG VERSION)
  const handleAnalyse = async () => {
    console.log("🔥 ANALYSE CLICKED");

    if (!file) {
      alert("Please upload a file first");
      return;
    }

    setLoading(true);
    setError(null);

    try {
      const formData = new FormData();
      formData.append("file", file);

      console.log("📤 Sending to backend...");

      const response = await fetch("http://127.0.0.1:8000/analyze", {
        method: "POST",
        body: formData,
      });

      console.log("📡 RESPONSE STATUS:", response.status);

      const data = await response.json();

      console.log("📦 BACKEND RESPONSE:", data);

      if (!response.ok) {
        throw new Error(data.detail || "Backend error");
      }

      setReport({
        message: data.status || "No status returned",
        features: data.features || {},
        image: preview,
      });

    } catch (err) {
      console.error("❌ ANALYSE ERROR:", err);
      setError(err.message || "Unknown error connecting to backend");
    }

    setLoading(false);
  };

  return (
    <div style={{ minHeight: "100vh", backgroundColor: "#f3f4f6", display: "flex", flexDirection: "column", alignItems: "center" }}>
      
      {/* NAVBAR */}
      <div style={{ width: "100%", backgroundColor: "#e5e7eb", display: "flex", justifyContent: "space-between", padding: "12px 32px" }}>
        <img src="/logo-left.png" alt="logo" style={{ height: "32px" }} />
        <img src="/logo-center.png" alt="logo" style={{ height: "36px" }} />
        <div style={{ width: "80px", height: "24px", backgroundColor: "black", borderRadius: "999px" }} />
      </div>

      {/* MAIN CONTENT */}
      <div style={{ width: "100%", maxWidth: "1100px", backgroundColor: "white", marginTop: "16px", padding: "32px", borderRadius: "16px" }}>
        
        <h2 style={{ fontSize: "28px", color: "#3b82f6", fontWeight: "700" }}>
          AI Accessibility Audit Tool
        </h2>

        <p style={{ color: "#4b5563" }}>
          Upload transport images and get instant accessibility analysis.
        </p>

        {/* ERROR BOX */}
        {error && (
          <div style={{ marginTop: "16px", padding: "12px", backgroundColor: "#fee2e2", color: "#b91c1c", borderRadius: "8px" }}>
            ❌ {error}
          </div>
        )}

        <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "32px", marginTop: "24px" }}>
          
          {/* LEFT */}
          <div>
            <h3>Steps</h3>
            <ol>
              <li>Upload image</li>
              <li>Click Analyse</li>
              <li>View results</li>
            </ol>
          </div>

          {/* RIGHT */}
          <div style={{ display: "flex", flexDirection: "column", gap: "12px" }}>
            
            {/* UPLOAD */}
            <div
              onClick={handleUploadClick}
              style={{
                height: "180px",
                backgroundColor: "#e5e7eb",
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                borderRadius: "12px",
                cursor: "pointer"
              }}
            >
              Click to Upload
              <input
                ref={fileInputRef}
                type="file"
                style={{ display: "none" }}
                onChange={handleFileChange}
              />
            </div>

            {/* PREVIEW */}
            {preview && (
              <img
                src={preview}
                alt="preview"
                style={{ width: "100%", borderRadius: "12px" }}
              />
            )}

            {/* ANALYSE BUTTON */}
            <button
              onClick={handleAnalyse}
              disabled={loading}
              style={{
                padding: "10px",
                backgroundColor: loading ? "#9ca3af" : "#3b82f6",
                color: "white",
                border: "none",
                borderRadius: "8px",
                cursor: "pointer"
              }}
            >
              {loading ? "Analyzing..." : "Analyse"}
            </button>

            {/* LOADING SPINNER */}
            {loading && (
              <p style={{ color: "#6b7280" }}>
                ⏳ Processing image...
              </p>
            )}
          </div>
        </div>

        {/* REPORT */}
        {report && (
          <div style={{ marginTop: "32px", padding: "20px", backgroundColor: "#f9fafb", borderRadius: "12px" }}>
            
            <h3>Report</h3>

            <p><b>Status:</b> {report.message}</p>

            {report.features && (
              <ul>
                {Object.entries(report.features).map(([key, value]) => (
                  <li key={key}>
                    {key}: {String(value)}
                  </li>
                ))}
              </ul>
            )}

            {report.image && (
              <img
                src={report.image}
                alt="report"
                style={{ width: "100%", marginTop: "12px", borderRadius: "12px" }}
              />
            )}
          </div>
        )}
      </div>
    </div>
  );
}