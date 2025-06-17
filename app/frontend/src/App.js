import React, { useState } from 'react';
import VisitorCounter from './VisitorCounter';
import './App.css';

// Get API URL from environment variable or default to backend service
const API_URL = process.env.REACT_APP_API_URL || 'http://backend-service:3001';

function App() {
  const [formData, setFormData] = useState({
    name: '',
    email: '',
    project: '',
    message: ''
  });
  const [submitStatus, setSubmitStatus] = useState('');
  const [isSubmitting, setIsSubmitting] = useState(false);

  const handleChange = (e) => {
    setFormData({
      ...formData,
      [e.target.name]: e.target.value
    });
  };

  const handleSubmit = async (e) => {
    e.preventDefault();
    setIsSubmitting(true);
    setSubmitStatus('');

    try {
      const response = await fetch(`${API_URL}/api/contact`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(formData),
      });

      if (response.ok) {
        setSubmitStatus('success');
        setFormData({ name: '', email: '', project: '', message: '' });
      } else {
        setSubmitStatus('error');
      }
    } catch (error) {
      console.error('Error submitting form:', error);
      setSubmitStatus('error');
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <div className="App">
      <header className="header">
        <div className="container">
          <h1 className="logo">Retoucher Irving</h1>
          <p className="tagline">Professional Photo Editing & Retouching Services</p>
        </div>
      </header>

      <main className="main">
        <div className="container">
          <section className="hero">
            <h2>Transform Your Photos Into Art</h2>
            <p>
              Professional photo retouching and editing services for photographers, 
              businesses, and individuals. From basic adjustments to complex composites, 
              we bring your vision to life.
            </p>
          </section>

          <section className="services">
            <h3>Our Services</h3>
            <div className="service-grid">
              <div className="service-card">
                <h4>Portrait Retouching</h4>
                <p>Professional headshots, fashion photography, and beauty retouching</p>
              </div>
              <div className="service-card">
                <h4>Product Photography</h4>
                <p>E-commerce optimization, background removal, and color correction</p>
              </div>
              <div className="service-card">
                <h4>Wedding Photography</h4>
                <p>Romantic enhancement, skin smoothing, and atmospheric adjustments</p>
              </div>
              <div className="service-card">
                <h4>Real Estate</h4>
                <p>Property enhancement, sky replacement, and lighting optimization</p>
              </div>
            </div>
          </section>

          <section className="contact">
            <h3>Get Started Today</h3>
            <form onSubmit={handleSubmit} className="contact-form">
              <div className="form-group">
                <input
                  type="text"
                  name="name"
                  placeholder="Your Name"
                  value={formData.name}
                  onChange={handleChange}
                  required
                />
              </div>
              <div className="form-group">
                <input
                  type="email"
                  name="email"
                  placeholder="Your Email"
                  value={formData.email}
                  onChange={handleChange}
                  required
                />
              </div>
              <div className="form-group">
                <select
                  name="project"
                  value={formData.project}
                  onChange={handleChange}
                  required
                >
                  <option value="">Select Project Type</option>
                  <option value="portrait">Portrait Retouching</option>
                  <option value="product">Product Photography</option>
                  <option value="wedding">Wedding Photography</option>
                  <option value="real-estate">Real Estate</option>
                  <option value="other">Other</option>
                </select>
              </div>
              <div className="form-group">
                <textarea
                  name="message"
                  placeholder="Tell us about your project..."
                  value={formData.message}
                  onChange={handleChange}
                  rows="5"
                  required
                ></textarea>
              </div>
              <button 
                type="submit" 
                className="submit-btn"
                disabled={isSubmitting}
              >
                {isSubmitting ? 'Sending...' : 'Send Message'}
              </button>
              
              {submitStatus === 'success' && (
                <p className="status-message success">
                  Thank you! We'll get back to you within 24 hours.
                </p>
              )}
              {submitStatus === 'error' && (
                <p className="status-message error">
                  Sorry, there was an error sending your message. Please try again.
                </p>
              )}
            </form>
          </section>

          <VisitorCounter />
        </div>
      </main>

      <footer className="footer">
        <div className="container">
          <p>&copy; 2025 Retoucher Irving. All rights reserved.</p>
        </div>
      </footer>
    </div>
  );
}

export default App;