import { useState, useCallback } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useToast } from "@/hooks/use-toast";
import { useLocation } from "wouter";
import { isUnauthorizedError } from "@/lib/authUtils";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { CloudUpload, FileText, CheckCircle } from "lucide-react";
import { useDropzone } from "react-dropzone";

export default function CSVImport() {
  const { toast } = useToast();
  const queryClient = useQueryClient();
  const [, setLocation] = useLocation();
  const [uploadedFile, setUploadedFile] = useState<File | null>(null);

  const importMutation = useMutation({
    mutationFn: async (file: File) => {
      const formData = new FormData();
      formData.append('csvFile', file);
      
      const response = await fetch('/api/flights/import-csv', {
        method: 'POST',
        body: formData,
        credentials: 'include',
      });

      if (!response.ok) {
        const error = await response.text();
        throw new Error(`${response.status}: ${error}`);
      }

      return response.json();
    },
    onSuccess: (data) => {
      toast({
        title: "Import Successful",
        description: `Successfully imported ${data.flights} flights!`,
      });
      queryClient.invalidateQueries({ queryKey: ["/api/flights"] });
      queryClient.invalidateQueries({ queryKey: ["/api/stats"] });
      setLocation("/flights");
    },
    onError: (error) => {
      if (isUnauthorizedError(error)) {
        toast({
          title: "Unauthorized",
          description: "You are logged out. Logging in again...",
          variant: "destructive",
        });
        setTimeout(() => {
          window.location.href = "/api/login";
        }, 500);
        return;
      }
      toast({
        title: "Import Failed",
        description: "Failed to import CSV file. Please check the format and try again.",
        variant: "destructive",
      });
    },
  });

  const onDrop = useCallback((acceptedFiles: File[]) => {
    const file = acceptedFiles[0];
    if (file && file.type === 'text/csv') {
      setUploadedFile(file);
    } else {
      toast({
        title: "Invalid File",
        description: "Please select a valid CSV file.",
        variant: "destructive",
      });
    }
  }, [toast]);

  const { getRootProps, getInputProps, isDragActive } = useDropzone({
    onDrop,
    accept: {
      'text/csv': ['.csv']
    },
    multiple: false
  });

  const handleImport = () => {
    if (uploadedFile) {
      importMutation.mutate(uploadedFile);
    }
  };

  const handleRemoveFile = () => {
    setUploadedFile(null);
  };

  return (
    <div className="space-y-6">
      {/* File Upload Area */}
      <div 
        {...getRootProps()}
        className={`border-2 border-dashed rounded-lg p-8 text-center transition-colors cursor-pointer ${
          isDragActive 
            ? "border-aviation-blue bg-blue-50" 
            : "border-slate-300 hover:border-aviation-blue"
        }`}
      >
        <input {...getInputProps()} />
        
        {uploadedFile ? (
          <div className="space-y-4">
            <CheckCircle className="w-12 h-12 text-green-500 mx-auto" />
            <div>
              <p className="text-lg font-medium text-slate-900">{uploadedFile.name}</p>
              <p className="text-sm text-slate-600">
                {(uploadedFile.size / 1024).toFixed(1)} KB • CSV File
              </p>
            </div>
            <Button variant="outline" onClick={handleRemoveFile}>
              Remove File
            </Button>
          </div>
        ) : (
          <div className="space-y-4">
            <CloudUpload className="w-12 h-12 text-slate-400 mx-auto" />
            <div>
              <p className="text-lg font-medium text-slate-900">Upload your flight data</p>
              <p className="text-sm text-slate-600">
                Drag and drop your CSV file here, or click to browse
              </p>
            </div>
            <Button variant="outline" className="bg-aviation-blue text-white hover:bg-blue-700">
              Choose File
            </Button>
          </div>
        )}
      </div>

      {/* Format Info */}
      <Card>
        <CardContent className="p-4">
          <div className="flex items-start space-x-3">
            <FileText className="w-5 h-5 text-aviation-blue mt-0.5" />
            <div>
              <h4 className="text-sm font-medium text-aviation-blue mb-2">CSV Format Requirements:</h4>
              <ul className="text-xs text-slate-600 space-y-1">
                <li>• Date, Flight number, From, To, Dep time, Arr time</li>
                <li>• Duration, Airline, Aircraft, Registration, Seat number</li>
                <li>• Seat type, Flight class, Flight reason, Note</li>
                <li>• First row should contain column headers</li>
                <li>• Airport format: "City / Airport Name (CODE/ICAO)"</li>
                <li>• Airline format: "Airline Name (CODE/ICAO)"</li>
              </ul>
            </div>
          </div>
        </CardContent>
      </Card>

      {/* Action Buttons */}
      <div className="flex justify-end space-x-3">
        <Button 
          variant="outline" 
          onClick={() => setLocation("/flights")}
          disabled={importMutation.isPending}
        >
          Cancel
        </Button>
        <Button 
          onClick={handleImport}
          disabled={!uploadedFile || importMutation.isPending}
          className="bg-aviation-blue hover:bg-blue-700"
        >
          {importMutation.isPending ? "Importing..." : "Import Flights"}
        </Button>
      </div>
    </div>
  );
}
