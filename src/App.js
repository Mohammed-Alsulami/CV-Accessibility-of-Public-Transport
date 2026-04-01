import React, { useState } from "react";

function App() {
  const [file, setFile] = useState(null);
  const [preview, setPreview] = useState(null);
  const [result, setResult] = useState("");

  const handleFileChange = (e) => {
    const selectedFile = e.target.files[0];
    setFile(selectedFile);

    if (selectedFile) {
      setPreview(URL.createObjectURL(selectedFile));
    }
  };

  const handleSubmit = () => {
    // placeholder result (later this will call FastAPI)
    setResult("Tactile flooring detected near platform edge");
  };

  return (
    <div style={{ padding: "20px", fontFamily: "Arial" }}>
      
      <h1>Accessibility Audit Tool</h1>

      <p>Upload an image of a tram or train stop.</p>

      <input type="file" accept="image/*" onChange={handleFileChange} />

      <br /><br />

      {preview && (
        <div>
          <h3>Preview:</h3>
          <img
            src={preview}
            alt="preview"
            style={{ width: "300px", borderRadius: "8px" }}
          />
        </div>
      )}

      <br />

      <button onClick={handleSubmit} disabled={!file}>
        Run Analysis
      </button>

      <br /><br />

      {result && (
        <div style={{ padding: "10px", background: "#f0f0f0" }}>
          <h3>Result:</h3>
          <p>{result}</p>
        </div>
      )}
    </div>
  );
}

export default App;