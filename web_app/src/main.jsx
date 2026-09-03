import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { BrowserRouter } from 'react-router-dom'
import App from './App.jsx'
import './index.css'
import { AdminDataProvider } from './state/AdminDataContext'
import { AuthProvider } from './state/AuthContext'
import { DoctorDataProvider } from './state/DoctorDataContext'
import { LanguageProvider } from './state/LanguageContext'
import { PatientDataProvider } from './state/PatientDataContext'
import { ThemeProvider } from './state/ThemeContext'

createRoot(document.getElementById('root')).render(
  <StrictMode>
    <BrowserRouter>
      <ThemeProvider>
        <AuthProvider>
          <LanguageProvider>
            <PatientDataProvider>
              <DoctorDataProvider>
                <AdminDataProvider>
                  <App />
                </AdminDataProvider>
              </DoctorDataProvider>
            </PatientDataProvider>
          </LanguageProvider>
        </AuthProvider>
      </ThemeProvider>
    </BrowserRouter>
  </StrictMode>,
)
