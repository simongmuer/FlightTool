# FlightTool - Personal Flight Tracking Application

A comprehensive full-stack web application for personal flight tracking and management. Built with React, Express.js, and PostgreSQL.

## Features

- **User Authentication**: Secure login system using Replit Auth with OpenID Connect
- **Flight Management**: Add, view, edit, and delete flight records with comprehensive details
- **CSV Import**: Bulk import flight data from CSV files with automatic parsing
- **Interactive Dashboard**: Overview with flight statistics, charts, and analytics
- **Flight Search**: Search and filter flights by various criteria
- **Map Visualization**: Placeholder for future interactive flight route mapping
- **Responsive Design**: Modern aviation-themed UI that works on all devices

## Tech Stack

### Frontend
- **React 18** with TypeScript
- **Vite** for fast development and optimized builds
- **Wouter** for lightweight routing
- **shadcn/ui** component library with Radix UI primitives
- **Tailwind CSS** for styling
- **TanStack Query** for server state management
- **React Hook Form** with Zod validation

### Backend
- **Node.js** with Express.js
- **TypeScript** with ES modules
- **PostgreSQL** with Drizzle ORM
- **Replit Auth** with OpenID Connect
- **Express Sessions** with PostgreSQL storage
- **Multer** for file uploads

## Project Structure

```
├── client/                 # Frontend React application
│   ├── src/
│   │   ├── components/     # Reusable UI components
│   │   ├── pages/          # Application pages
│   │   ├── hooks/          # Custom React hooks
│   │   ├── lib/            # Utility functions
│   │   └── App.tsx         # Main application component
├── server/                 # Backend Express application
│   ├── index.ts           # Server entry point
│   ├── routes.ts          # API route definitions
│   ├── storage.ts         # Database operations
│   ├── db.ts              # Database configuration
│   └── replitAuth.ts      # Authentication setup
├── shared/                 # Shared type definitions
│   └── schema.ts          # Database schema and types
└── attached_assets/       # CSV import files
```

## Setup Instructions

1. **Clone the repository**:
   ```bash
   git clone <your-repo-url>
   cd flighttool
   ```

2. **Install dependencies**:
   ```bash
   npm install
   ```

3. **Set up environment variables**:
   - `DATABASE_URL` - PostgreSQL connection string
   - `SESSION_SECRET` - Session encryption secret
   - `REPLIT_DOMAINS` - Comma-separated list of allowed domains
   - `REPL_ID` - Replit application ID for auth

4. **Set up the database**:
   ```bash
   npm run db:push
   ```

5. **Start the development server**:
   ```bash
   npm run dev
   ```

The application will be available at `http://localhost:5000`

## Database Schema

The database schema is automatically created when the application starts. No manual setup required.

- **Users**: User profiles with authentication (ID, username, password, email, profile info)
- **Flights**: Core flight data including dates, airports, airlines, aircraft details, and notes
- **Airlines**: Reference data for airline information (automatically seeded)
- **Airports**: Reference data for airport information (automatically seeded)
- **Sessions**: Session storage for user authentication (PostgreSQL-backed)

## CSV Import Format

The application supports importing flight data from CSV files with the following columns:

- Date, Flight Number, From Airport, To Airport
- Departure/Arrival Times, Duration, Airline
- Aircraft Type, Registration, Seat Information
- Flight Class, Reason, Notes

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## License

MIT License - feel free to use this project for personal or commercial purposes.

## Deployment

This application is designed to run on Replit with minimal configuration, but can be deployed on any platform that supports Node.js and PostgreSQL.

For Replit deployment:
1. Ensure all environment variables are configured
2. The application will automatically handle authentication and database connections
3. Use Replit's deployment feature for production hosting

---

Built with ❤️ for aviation enthusiasts who want to track their flights comprehensively.