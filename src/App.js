import React, { useState } from "react";

function App() {
  const [file, setFile] = useState(null);
  const [preview, setPreview] = useState(null);
  const [result, setResult] = useState("");

  const handleFileChange = (e) => {
    const selected = e.target.files[0];
    setFile(selected);

    if (selected) {
      setPreview(URL.createObjectURL(selected));
      setResult("");
    }
  };

  const handleSubmit = () => {
    setResult("Tactile flooring detected near platform edge (mock result)");
  };

  return (
    <div style={styles.page}>
      
      {/* Header */}
      <div style={styles.header}>
        <h1 style={styles.title}>Accessibility Audit Tool</h1>
        <p style={styles.subtitle}>
          Detect accessibility features in public transport environments
        </p>
      </div>

      {/* Main Card */}
      <div style={styles.card}>
        
        <input
          type="file"
          accept="image/*"
          onChange={handleFileChange}
          style={styles.input}
        />

        {preview && (
          <div style={styles.previewBox}>
            <img src={preview} alt="preview" style={styles.image} />
          </div>
        )}

        <button
          onClick={handleSubmit}
          disabled={!file}
          style={{
            ...styles.button,
            opacity: file ? 1 : 0.5,
            cursor: file ? "pointer" : "not-allowed",
          }}
        >
          Run Analysis
        </button>

        {result && (
          <div style={styles.resultBox}>
            <h3 style={{ margin: 0 }}>Result</h3>
            <p style={{ marginTop: 8 }}>{result}</p>
          </div>
        )}
      </div>
    </div>
  );
}

const styles = {
  page: {
    fontFamily: "Arial, sans-serif",
    background: "#f5f9ff",
    minHeight: "100vh",
    padding: "40px",
  },

  header: {
    textAlign: "center",
    marginBottom: "30px",
  },

  title: {
    color: "#2d88ff",
    marginBottom: "5px",
  },

  subtitle: {
    color: "#555",
    fontSize: "14px",
  },

  card: {
    maxWidth: "500px",
    margin: "0 auto",
    background: "#fff",
    padding: "25px",
    borderRadius: "12px",
    boxShadow: "0 8px 20px rgba(0,0,0,0.08)",
    textAlign: "center",
  },

  input: {
    marginBottom: "20px",
  },

  previewBox: {
    marginBottom: "20px",
  },

  image: {
    width: "100%",
    borderRadius: "10px",
    border: "2px solid #e6f0ff",
  },

  button: {
    background: "#2d88ff",
    color: "white",
    border: "none",
    padding: "12px 18px",
    borderRadius: "8px",
    fontSize: "14px",
    fontWeight: "bold",
    transition: "0.2s",
  },

  resultBox: {
    marginTop: "20px",
    padding: "15px",
    background: "#eaf2ff",
    borderRadius: "10px",
    borderLeft: "4px solid #2d88ff",
    textAlign: "left",
  },
};

export default App;
